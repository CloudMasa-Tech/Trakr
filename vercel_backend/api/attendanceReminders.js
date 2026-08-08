// Cron job: sends check-in / check-out reminder pushes near the configured
// cutoff times, plus a follow-up reminder after checkout closes.
// Ports the removed Cloud Functions `sendAttendanceReminderNotifications`
// pubsub job.
const { admin, initializeFirebaseAdmin } = require('../lib/firebaseAdmin');
const {
  checkoutConfigForDate,
  collectTokensForRecipient,
  dateKeyFor,
  isAuthorizedCronRequest,
} = require('../lib/helpers');

function activeDirectoryMember(data) {
  const status = String(data.status || 'active').trim().toLowerCase();
  const isActive = typeof data.isActive === 'boolean' ? data.isActive : true;
  return isActive && status !== 'inactive';
}

function directoryEmployeeId(doc) {
  const data = doc.data() || {};
  return String(data.employeeId || doc.id || '').trim();
}

async function collectScannerUsers(db) {
  const members = new Map();
  for (const collectionName of ['staff', 'managers']) {
    const snap = await db.collection(collectionName).limit(500).get();
    snap.forEach((doc) => {
      const data = doc.data() || {};
      if (!activeDirectoryMember(data)) return;
      const employeeId = directoryEmployeeId(doc);
      if (!employeeId) return;
      members.set(employeeId, {
        employeeId,
        employeeName: data.name || employeeId,
        email: data.email || '',
        collectionName,
      });
    });
  }
  return Array.from(members.values());
}

async function attendanceByEmployeeForDate(db, dateKey) {
  const snap = await db
    .collection('attendance')
    .where('dateKey', '==', dateKey)
    .get();
  const records = new Map();
  snap.forEach((doc) => {
    const data = doc.data() || {};
    const employeeId = String(data.employeeId || '').trim();
    if (employeeId) records.set(employeeId, data);
  });
  return records;
}

// Writes the reminder notification (idempotent by deterministic id) and, when
// the write succeeds, pushes it to the employee's devices.
async function writeReminderAndPush({
  db,
  id,
  recipient,
  employeeId,
  employeeName,
  title,
  content,
  type,
  actionType,
  dateKey,
}) {
  const notification = {
    recipient,
    employeeId,
    employeeName: employeeName || '',
    type,
    title,
    content,
    actionType,
    status: 'Sent',
    dateKey,
    notificationFormat: 'dynamic',
    notificationTitle: title,
    notificationBody: content,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  };

  let created = false;
  await db.collection('notifications').doc(id).create(notification)
    .then(() => {
      created = true;
    })
    .catch((error) => {
      if (error.code !== 6 && error.code !== 'already-exists') {
        throw error;
      }
    });

  if (!created) {
    return { skipped: true, successCount: 0, failureCount: 0 };
  }

  const tokens = await collectTokensForRecipient(db, employeeId || recipient);
  if (tokens.length === 0) {
    return { skipped: false, successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  const push = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title,
      body: content,
    },
    data: {
      actionType,
      type,
      dateKey,
      notificationFormat: 'dynamic',
      notificationTitle: title,
      notificationBody: content,
      notificationTag: actionType,
    },
    android: {
      priority: 'high',
      collapseKey: actionType,
      notification: {
        channelId: 'high_importance_channel',
        tag: actionType,
        priority: 'high',
        sound: 'default',
        defaultSound: true,
        visibility: 'public',
      },
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          alert: { title, body: content },
          sound: 'default',
        },
      },
    },
    webpush: {
      notification: {
        title,
        body: content,
        tag: actionType,
      },
    },
  });

  await db.collection('notifications').doc(id).set({
    pushStatus: push.failureCount > 0 ? 'partial' : 'sent',
    pushSuccessCount: push.successCount,
    pushFailureCount: push.failureCount,
    pushTokenCount: tokens.length,
    pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    skipped: false,
    successCount: push.successCount,
    failureCount: push.failureCount,
    tokenCount: tokens.length,
  };
}

async function runAttendanceReminders() {
  if (!initializeFirebaseAdmin()) {
    throw new Error('Firebase Admin not initialized. Check FIREBASE_SERVICE_ACCOUNT.');
  }

  const db = admin.firestore();
  const now = new Date();
  const todayKey = dateKeyFor(now);
  const {
    checkInEnd,
    checkInEndTime,
    checkOutEnd,
    checkOutEndTime,
  } = await checkoutConfigForDate(db, now);

  const checkInDiffMin = (checkInEndTime.getTime() - now.getTime()) / 60000;
  const checkOutDiffMin = (checkOutEndTime.getTime() - now.getTime()) / 60000;

  const sendCheckIn30 = checkInDiffMin > 25 && checkInDiffMin <= 30;
  const sendCheckOut30 = checkOutDiffMin > 25 && checkOutDiffMin <= 30;
  const sendCheckOut15 = checkOutDiffMin > 10 && checkOutDiffMin <= 15;
  const sendCheckOut10 = checkOutDiffMin > 5 && checkOutDiffMin <= 10;
  const afterCheckOutDiffMin = (now.getTime() - checkOutEndTime.getTime()) / 60000;
  const sendCheckOutAfter = afterCheckOutDiffMin > 25 && afterCheckOutDiffMin <= 30;

  if (!sendCheckIn30 && !sendCheckOut30 && !sendCheckOut15 && !sendCheckOut10 && !sendCheckOutAfter) {
    return { created: 0, pushSuccessCount: 0, pushFailureCount: 0 };
  }

  const [members, attendanceMap] = await Promise.all([
    collectScannerUsers(db),
    attendanceByEmployeeForDate(db, todayKey),
  ]);

  const writes = [];
  for (const member of members) {
    const record = attendanceMap.get(member.employeeId);

    if (sendCheckIn30 && !record?.checkInTime) {
      writes.push(writeReminderAndPush({
        db,
        id: `checkin_reminder_${todayKey}_${member.employeeId}`,
        recipient: member.employeeId,
        employeeId: member.employeeId,
        employeeName: member.employeeName,
        type: 'Check-In Reminder',
        title: 'Check-In Reminder',
        content: `Reminder: you have only half an hour to check in. Check-in closes at ${checkInEnd}.`,
        actionType: 'checkin_reminder',
        dateKey: todayKey,
      }));
    }

    if (!record?.checkInTime || record?.checkOutTime) continue;

    if (sendCheckOut30) {
      writes.push(writeReminderAndPush({
        db,
        id: `checkout_30_reminder_${todayKey}_${member.employeeId}`,
        recipient: member.employeeId,
        employeeId: member.employeeId,
        employeeName: member.employeeName,
        type: 'Check-Out Reminder',
        title: 'Checkout Reminder',
        content: `⏰ Checkout Reminder\nYour workday is about to end. so remember to check out before your shift ends.`,
        actionType: 'checkout_reminder_30',
        dateKey: todayKey,
      }));
    }

    if (sendCheckOut15) {
      writes.push(writeReminderAndPush({
        db,
        id: `checkout_15_reminder_${todayKey}_${member.employeeId}`,
        recipient: member.employeeId,
        employeeId: member.employeeId,
        employeeName: member.employeeName,
        type: 'Check-Out Reminder',
        title: 'Checkout Reminder',
        content: `🔔 Checkout Reminder\nYou haven't checked out yet. Please complete your checkout before the end of your shift.`,
        actionType: 'checkout_reminder_15',
        dateKey: todayKey,
      }));
    }

    if (sendCheckOut10) {
      writes.push(writeReminderAndPush({
        db,
        id: `checkout_10_reminder_${todayKey}_${member.employeeId}`,
        recipient: member.employeeId,
        employeeId: member.employeeId,
        employeeName: member.employeeName,
        type: 'Check-Out Reminder',
        title: 'Checkout Reminder',
        content: `⚠️ Checkout Reminder \nYour shift will end in 10 minutes. Please check out to complete today's attendance.`,
        actionType: 'checkout_reminder_10',
        dateKey: todayKey,
      }));
    }

    if (sendCheckOutAfter) {
      writes.push(writeReminderAndPush({
        db,
        id: `checkout_after_reminder_${todayKey}_${member.employeeId}`,
        recipient: member.employeeId,
        employeeId: member.employeeId,
        employeeName: member.employeeName,
        type: 'Check-Out Reminder',
        title: 'Check-Out Reminder',
        content: `Reminder: you have not checked out yet. Please check out before the one-hour limit ends.`,
        actionType: 'checkout_after_reminder',
        dateKey: todayKey,
      }));
    }
  }

  const results = await Promise.all(writes);
  const created = results.filter((result) => !result.skipped).length;
  const pushSuccessCount = results.reduce((sum, result) => sum + (result.successCount || 0), 0);
  const pushFailureCount = results.reduce((sum, result) => sum + (result.failureCount || 0), 0);

  return { created, pushSuccessCount, pushFailureCount };
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type, X-Cron-Secret',
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed. Use GET or POST.' });
  }

  if (!isAuthorizedCronRequest(req)) {
    return res.status(401).json({ error: 'Unauthorized.' });
  }

  try {
    const result = await runAttendanceReminders();
    return res.status(200).json({
      success: true,
      message: 'Attendance reminders completed.',
      ...result,
    });
  } catch (error) {
    console.error('Attendance reminders failed:', error);
    return res.status(500).json({
      error: 'Attendance reminders failed.',
      details: error.message,
    });
  }
}
