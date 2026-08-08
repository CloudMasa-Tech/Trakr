// Cron job: scans the last 7 days of `attendance` for missing checkouts and
// creates actionable approve requests + pushes them to admins.
// Ports the removed Cloud Functions `syncMissedCheckoutRequests` pubsub job.
const { admin, initializeFirebaseAdmin } = require('../lib/firebaseAdmin');
const {
  checkoutConfigForDate,
  cleanNotificationText,
  collectAdminTokens,
  dateKeyFor,
  isAuthorizedCronRequest,
  staffDirectoryData,
} = require('../lib/helpers');

async function runSyncMissedCheckout() {
  if (!initializeFirebaseAdmin()) {
    throw new Error('Firebase Admin not initialized. Check FIREBASE_SERVICE_ACCOUNT.');
  }

  const db = admin.firestore();
  const now = new Date();
  const lookbackStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7);
  const attendanceSnap = await db
    .collection('attendance')
    .where('date', '>=', admin.firestore.Timestamp.fromDate(lookbackStart))
    .get();

  const writes = [];
  const pendingPush = [];

  for (const attendanceDoc of attendanceSnap.docs) {
    const data = attendanceDoc.data() || {};
    if (data.checkOutTime || !data.checkInTime) continue;

    const employeeId = String(data.employeeId || '').trim();
    if (!employeeId) continue;

    const attendanceDate = data.date?.toDate?.() || new Date();
    const dateKey = data.dateKey || dateKeyFor(attendanceDate);
    const { checkOutEndTime } = await checkoutConfigForDate(db, attendanceDate);
    const graceEndsAt = new Date(checkOutEndTime.getTime() + 60 * 60 * 1000);
    if (now < graceEndsAt) continue;

    const requestRef = db.collection('checkout_requests').doc(`${employeeId}_${dateKey}`);
    const existing = await requestRef.get();
    if (existing.exists) continue;

    const staff = await staffDirectoryData(db, employeeId);
    const employeeName = data.employeeName || staff.name || '';

    writes.push(requestRef.set({
      attendanceId: attendanceDoc.id,
      employeeId,
      employeeName,
      department: data.department || staff.department || '',
      email: staff.email || '',
      phone: staff.phone || '',
      dateKey,
      checkInTime: data.checkInTime,
      checkoutDeadline: admin.firestore.Timestamp.fromDate(checkOutEndTime),
      checkoutGraceEndsAt: admin.firestore.Timestamp.fromDate(graceEndsAt),
      status: 'pending',
      queryMessage:
        'The employee did not check out within the configured checkout window or the one-hour grace period. Contact the employee to verify why checkout was missed before approving.',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }));

    writes.push(db.collection('notifications').add({
      recipient: 'Admin',
      type: 'Checkout Request',
      title: 'Missed Check-Out',
      content: `⏰ ${employeeName || employeeId} missed check-out.`,
      actionType: 'checkout_request',
      notificationFormat: 'dynamic',
      notificationTitle: 'Missed Check-Out',
      notificationBody: `⏰ ${employeeName || employeeId} missed check-out.`,
      notificationTag: `checkout_${requestRef.id}`,
      requestCollection: 'checkout_requests',
      requestId: requestRef.id,
      employeeId,
      employeeName,
      dateKey,
      primaryAction: 'approve',
      primaryActionLabel: 'Approve',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      read: false,
    }));
  }

  const written = writes.length;
  await Promise.all(writes);

  // With no Firestore trigger, push the actionable notifications to admins
  // directly.
  let pushSuccessCount = 0;
  let pushFailureCount = 0;
  const notificationSnap = await db
    .collection('notifications')
    .where('actionType', '==', 'checkout_request')
    .where('status', '==', 'Sent')
    .orderBy('timestamp', 'desc')
    .limit(20)
    .get();

  if (!notificationSnap.empty) {
    const tokens = await collectAdminTokens(db);
    if (tokens.length > 0) {
      const pushes = [];
      notificationSnap.forEach((doc) => {
        const notif = doc.data() || {};
        pushes.push(
          admin.messaging().sendEachForMulticast({
            tokens,
            data: {
              ...Object.entries(notif).reduce((payload, [key, value]) => {
                if (value === undefined || value === null) return payload;
                payload[key] =
                  typeof value === 'string' ? value : JSON.stringify(value);
                return payload;
              }, {}),
              actionType: 'checkout_request',
              requestCollection: 'checkout_requests',
              requestId: String(notif.requestId || ''),
              notificationFormat: 'dynamic',
            },
            android: {
              priority: 'high',
              collapseKey: String(notif.notificationTag || 'checkout_request'),
            },
            apns: {
              headers: { 'apns-priority': '10' },
            },
          }).then((response) => {
            pushSuccessCount += response.successCount;
            pushFailureCount += response.failureCount;
          }),
        );
      });
      await Promise.all(pushes);
    }
  }

  return {
    checked: attendanceSnap.size,
    created: written / 2,
    pushSuccessCount,
    pushFailureCount,
  };
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
    const result = await runSyncMissedCheckout();
    return res.status(200).json({
      success: true,
      message: 'Missed checkout sync completed.',
      ...result,
    });
  } catch (error) {
    console.error('Missed checkout sync failed:', error);
    return res.status(500).json({
      error: 'Missed checkout sync failed.',
      details: error.message,
    });
  }
}
