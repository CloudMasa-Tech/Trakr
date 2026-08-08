// Shared helpers for the Vercel serverless backend.
// Centralizes Firebase token collection, FCM multicast sends, notification
// text cleanup, cron-secret auth, and time-schedule parsing used by the API
// endpoints and cron jobs.
const { admin, initializeFirebaseAdmin } = require('./firebaseAdmin');

function valueOf(data, key) {
  const value = data && data[key];
  return value === undefined || value === null ? '' : String(value).trim();
}

function removeBrandPrefix(value) {
  return String(value || '')
    .replace(/^T[ЯR]AKR\s*•\s*/i, '')
    .replace(/^T[ЯR]AKA\s*•\s*/i, '')
    .trim();
}

function removeBrandText(value) {
  return String(value || '')
    .replace(/\bT[ЯR]AKA\b\s*•?\s*/gi, '')
    .replace(/\bT[ЯR]AKR\b\s*•?\s*/gi, '')
    .replace(/\s+•\s+/g, ' • ')
    .trim();
}

function cleanNotificationText(value) {
  return removeBrandText(value)
    .replace(/\bstaff\s+check[\s\u2010-\u2015-]*out\s+recorded\b/gi, 'Work Session Closed')
    .replace(/\bstaff\s+check[\s\u2010-\u2015-]*in\s+recorded\b/gi, 'Secure Check-In')
    .replace(/\bstaff members?\b/gi, 'employee')
    .replace(/\bstaff\b/gi, 'employee')
    .trim();
}

function cleanNotificationTitle(title, body) {
  const cleanTitle = removeBrandText(removeBrandPrefix(cleanNotificationText(title)));
  const cleanBody = cleanNotificationText(body);
  if (/early\s+check[\s\u2010-\u2015-]*out/i.test(cleanTitle) ||
      /early\s+check[\s\u2010-\u2015-]*out/i.test(cleanBody)) {
    return 'Early Check-out Recorded';
  }
  if (/\bchecked\s+out\b/i.test(cleanBody)) {
    return 'Work Session Closed';
  }
  if (/\bchecked\s+in\b/i.test(cleanBody)) {
    return /\blate\b/i.test(cleanBody)
      ? 'Late Check-In Recorded'
      : 'Secure Check-In';
  }
  if (/\babsent\b/i.test(cleanTitle) || /\bno check[\s\u2010-\u2015-]*in\b/i.test(cleanBody)) {
    return 'Absent Marked';
  }
  if (/\bchecked in late\b/i.test(cleanNotificationText(body))) {
    return 'Late Check-In Recorded';
  }
  return cleanTitle;
}

function notificationTitle(type) {
  const cleanType = String(type || '').trim();
  if (!cleanType) return 'Attendance System';
  return cleanType
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function isDynamicNotification(notification) {
  const format = valueOf(notification, 'notificationFormat').toLowerCase();
  return format === 'dynamic' ||
    Boolean(valueOf(notification, 'notificationTitle')) ||
    Boolean(valueOf(notification, 'notificationBody')) ||
    !Boolean(valueOf(notification, 'attendanceAction'));
}

function notificationDisplay(notification) {
  const rawBody = notification.content ||
    notification.message ||
    'You have a new notification.';
  const rawTitle = notification.title || notificationTitle(notification.type);

  if (isDynamicNotification(notification)) {
    return {
      title: removeBrandPrefix(removeBrandText(
        valueOf(notification, 'notificationTitle') || String(rawTitle).trim(),
      )),
      body: removeBrandText(
        valueOf(notification, 'notificationBody') || String(rawBody).trim(),
      ),
    };
  }

  const body = cleanNotificationText(rawBody);
  return {
    title: cleanNotificationTitle(rawTitle, body),
    body,
  };
}

function fcmDataPayload(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) return undefined;
  return Object.entries(data).reduce((payload, [key, value]) => {
    if (value === undefined || value === null) return payload;
    payload[key] = typeof value === 'string' ? value : JSON.stringify(value);
    return payload;
  }, {});
}

function pushNotificationTag(data, fallback) {
  const explicitTag = valueOf(data, 'notificationTag');
  if (explicitTag) return explicitTag;

  const requestId = valueOf(data, 'requestId');
  if (requestId) {
    const collection = valueOf(data, 'requestCollection');
    return collection ? `${collection}_${requestId}` : requestId;
  }

  const attendanceAction = valueOf(data, 'attendanceAction');
  const employeeId = valueOf(data, 'employeeId');
  const dateKey = valueOf(data, 'dateKey');
  if (attendanceAction && employeeId && dateKey) {
    return `attendance_${attendanceAction}_${employeeId}_${dateKey}`;
  }

  return fallback || '';
}

function addTokensFromData(tokens, data) {
  if (!data) return;
  if (typeof data.fcmToken === 'string' && data.fcmToken.trim()) {
    tokens.add(data.fcmToken.trim());
  }
  if (Array.isArray(data.fcmTokens)) {
    data.fcmTokens.forEach((token) => {
      if (typeof token === 'string' && token.trim()) {
        tokens.add(token.trim());
      }
    });
  }
}

async function collectTokensFromQuery(tokens, query) {
  const snap = await query.get();
  snap.forEach((doc) => addTokensFromData(tokens, doc.data()));
}

async function collectUserTokens(db, tokens, collectionName, identifier) {
  const value = String(identifier || '').trim();
  if (!value) return;
  const collection = db.collection(collectionName);
  const lowerValue = value.toLowerCase();

  await Promise.all([
    collection.doc(value).get().then((doc) => addTokensFromData(tokens, doc.data())),
    collectTokensFromQuery(tokens, collection.where('employeeId', '==', value).limit(10)),
    collectTokensFromQuery(tokens, collection.where('email', '==', lowerValue).limit(10)),
    collectTokensFromQuery(tokens, collection.where('email', '==', value).limit(10)),
    collectTokensFromQuery(tokens, collection.where('name', '==', value).limit(10)),
    collectTokensFromQuery(tokens, collection.where('phone', '==', value).limit(10)),
  ]);
}

async function collectAdminTokens(db) {
  const tokens = new Set();
  await Promise.all([
    collectTokensFromQuery(tokens, db.collection('admins').limit(100)),
    collectTokensFromQuery(tokens, db.collection('users').where('role', '==', 'admin').limit(100)),
  ]);
  return Array.from(tokens);
}

async function collectAllTokens(db) {
  const tokens = new Set();
  await Promise.all(
    ['staff', 'managers', 'admins'].map((collectionName) =>
      collectTokensFromQuery(tokens, db.collection(collectionName).limit(500)),
    ),
  );
  await collectTokensFromQuery(tokens, db.collection('users').limit(500));
  return Array.from(tokens);
}

// Resolves an individual recipient (admin flag, employee id, uid, email,
// name or phone) to FCM tokens across the directory collections.
async function collectTokensForRecipient(db, recipient) {
  const tokens = new Set();
  const value = String(recipient || '').trim();
  if (!value) return [];

  if (value.toLowerCase() === 'admin') {
    await Promise.all([
      collectTokensFromQuery(tokens, db.collection('admins').limit(100)),
      collectTokensFromQuery(tokens, db.collection('users').where('role', '==', 'admin').limit(100)),
    ]);
    return Array.from(tokens);
  }

  await Promise.all(
    ['staff', 'managers', 'admins', 'users'].map((collectionName) =>
      collectUserTokens(db, tokens, collectionName, value),
    ),
  );

  return Array.from(tokens);
}

function dateKeyFor(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function parseConfiguredTime(baseDate, value, fallback) {
  const text = String(value || fallback).trim();
  const match = text.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  const source = match ? text : fallback;
  const parsed = source.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
  if (!parsed) {
    return new Date(
      baseDate.getFullYear(),
      baseDate.getMonth(),
      baseDate.getDate(),
      10,
      30,
      0,
      0,
    );
  }
  let hour = Number(parsed[1]);
  const minute = Number(parsed[2]);
  const period = parsed[3].toUpperCase();
  if (period === 'PM' && hour !== 12) hour += 12;
  if (period === 'AM' && hour === 12) hour = 0;
  return new Date(
    baseDate.getFullYear(),
    baseDate.getMonth(),
    baseDate.getDate(),
    hour,
    minute,
    0,
    0,
  );
}

async function checkoutConfigForDate(db, baseDate) {
  const geoDoc = await db.collection('geo_config').doc('default').get();
  const data = geoDoc.exists ? geoDoc.data() || {} : {};
  const checkInEnd = data.checkInEnd || '10:30 AM';
  const checkOutEnd = data.checkOutEnd || '07:30 PM';
  return {
    checkInEnd,
    checkInEndTime: parseConfiguredTime(baseDate, checkInEnd, '10:30 AM'),
    checkOutEnd,
    checkOutEndTime: parseConfiguredTime(baseDate, checkOutEnd, '07:30 PM'),
  };
}

async function staffDirectoryData(db, employeeId) {
  const cleanId = String(employeeId || '').trim();
  if (!cleanId) return {};
  for (const collectionName of ['staff', 'managers']) {
    const doc = await db.collection(collectionName).doc(cleanId).get();
    if (doc.exists) return doc.data() || {};
    const snap = await db
      .collection(collectionName)
      .where('employeeId', '==', cleanId)
      .limit(1)
      .get();
    if (!snap.empty) return snap.docs[0].data() || {};
  }
  return {};
}

function isAuthorizedCronRequest(req) {
  const cronSecret = process.env.CRON_SECRET || process.env.QR_CRON_SECRET;
  if (!cronSecret) return true;
  const bearer = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
  const headerSecret = String(req.headers['x-cron-secret'] || '');
  return bearer === cronSecret || headerSecret === cronSecret;
}

function isActionableRequest(data) {
  const actionType = String(data && data.actionType || '').trim().toLowerCase();
  return Boolean(data && data.requestId) &&
    ['leave_request', 'permission_request', 'checkout_request'].includes(actionType);
}

// Sends an FCM multicast push. Actionable requests (leave/permission/checkout
// approvals) are delivered as data messages so the client can render the
// approve/reject action buttons.
async function sendMulticast(tokens, { title, body, data, actionable }) {
  if (!tokens || tokens.length === 0) {
    return { successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  const messageData = {
    ...(fcmDataPayload(data) || {}),
    title: String(title),
    body: String(body),
    ...(pushNotificationTag(data) ? { notificationTag: pushNotificationTag(data) } : {}),
  };

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    ...(actionable ? {} : { notification: {
      title: String(title),
      body: String(body),
    } }),
    data: messageData,
    android: {
      priority: 'high',
      ...(pushNotificationTag(data) ? { collapseKey: pushNotificationTag(data) } : {}),
      ...(actionable ? {} : { notification: {
        channelId: 'high_importance_channel',
        ...(pushNotificationTag(data) ? { tag: pushNotificationTag(data) } : {}),
        priority: 'max',
        sound: 'default',
        defaultSound: true,
        visibility: 'public',
      } }),
    },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          alert: { title: String(title), body: String(body) },
          sound: 'default',
        },
      },
    },
    webpush: {
      notification: {
        title: String(title),
        body: String(body),
        ...(pushNotificationTag(data) ? { tag: pushNotificationTag(data) } : {}),
      },
    },
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
    tokenCount: tokens.length,
  };
}

async function notifyRequester(db, { employeeId, title, content, type }) {
  if (!employeeId) return;
  await db.collection('notifications').add({
    recipient: employeeId,
    employeeId,
    type,
    title,
    content,
    status: 'Sent',
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
  });
}

module.exports = {
  admin,
  initializeFirebaseAdmin,
  valueOf,
  removeBrandPrefix,
  removeBrandText,
  cleanNotificationText,
  cleanNotificationTitle,
  notificationTitle,
  isDynamicNotification,
  notificationDisplay,
  fcmDataPayload,
  pushNotificationTag,
  addTokensFromData,
  collectTokensFromQuery,
  collectUserTokens,
  collectAdminTokens,
  collectAllTokens,
  collectTokensForRecipient,
  dateKeyFor,
  parseConfiguredTime,
  checkoutConfigForDate,
  staffDirectoryData,
  isAuthorizedCronRequest,
  isActionableRequest,
  sendMulticast,
  notifyRequester,
};
