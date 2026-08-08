const admin = require('firebase-admin');
const crypto = require('crypto');

function initializeFirebaseAdmin() {
  if (admin.apps.length) return true;

  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    return true;
  } catch (error) {
    console.error('Error initializing Firebase Admin:', error);
    return false;
  }
}

function addTokensFromDoc(tokens, data) {
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

async function collectAdminTokens(db) {
  const tokens = new Set();
  const [adminsSnap, usersSnap] = await Promise.all([
    db.collection('admins').get(),
    db.collection('users').where('role', '==', 'admin').get(),
  ]);

  adminsSnap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
  usersSnap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
  return Array.from(tokens);
}

function cleanNotificationText(value) {
  return String(value || '')
    .replace(/^T[ЯR]AKR\s*•\s*/i, '')
    .replace(/^T[ЯR]AKA\s*•\s*/i, '')
    .replace(/\bT[ЯR]AKA\b\s*•?\s*/gi, '')
    .replace(/\bT[ЯR]AKR\b\s*•?\s*/gi, '')
    .replace(/\s+•\s+/g, ' • ')
    .trim();
}

async function sendAdminPush(db, { title, body, data }) {
  const tokens = await collectAdminTokens(db);
  if (tokens.length === 0) {
    return { successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  const displayTitle = cleanNotificationText(title);
  const displayBody = cleanNotificationText(body);
  const notificationTag = data?.notificationTag || data?.qrEvent || 'qr_code';
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: String(displayTitle),
      body: String(displayBody),
    },
    data: Object.entries(data || {}).reduce((payload, [key, value]) => {
      if (value === undefined || value === null) return payload;
      payload[key] = typeof value === 'string' ? value : JSON.stringify(value);
      return payload;
    }, {
      title: String(displayTitle),
      body: String(displayBody),
      notificationTag: String(notificationTag),
    }),
    android: {
      priority: 'high',
      collapseKey: String(notificationTag),
      notification: {
        channelId: 'high_importance_channel',
        tag: String(notificationTag),
        priority: 'max',
        sound: 'default',
        defaultSound: true,
        visibility: 'public',
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
      },
      payload: {
        aps: {
          alert: {
            title: String(displayTitle),
            body: String(displayBody),
          },
          sound: 'default',
        },
      },
    },
    webpush: {
      notification: {
        title: String(displayTitle),
        body: String(displayBody),
        tag: String(notificationTag),
      },
    },
  });

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
    tokenCount: tokens.length,
  };
}

function generateToken() {
  return crypto.randomBytes(24).toString('hex');
}

function dateKeyFor(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function daysUntilExpiry(now, expiresAt) {
  const dayMs = 24 * 60 * 60 * 1000;
  return Math.ceil((expiresAt.getTime() - now.getTime()) / dayMs);
}

async function loadGeoFenceRadius(db) {
  const [geoDoc, officeDoc] = await Promise.all([
    db.collection('geo_config').doc('default').get(),
    db.collection('offices').doc('default').get(),
  ]);
  const geoData = geoDoc.exists ? geoDoc.data() || {} : {};
  const officeData = officeDoc.exists ? officeDoc.data() || {} : {};
  const radius =
    geoData.radius ??
    geoData.geoFenceRadius ??
    officeData.radius ??
    officeData.geoFenceRadius ??
    50;
  return Number(radius) || 50;
}

async function writeNotificationAndPush(db, {
  id,
  tenantId,
  title,
  content,
  qrEvent,
  expiresAt,
  daysRemaining,
}) {
  const payload = {
    recipient: 'Admin',
    type: 'QR Code',
    title,
    content,
    status: 'Sent',
    suppressFirestorePush: true,
    actionType: 'qr_code',
    tenantId,
    qrEvent,
    read: false,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (expiresAt instanceof Date) {
    payload.expiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }
  if (daysRemaining !== undefined && daysRemaining !== null) {
    payload.daysRemaining = daysRemaining;
  }

  let created = false;
  await db.collection('notifications').doc(id).create(payload)
    .then(() => {
      created = true;
    })
    .catch((error) => {
      if (error.code !== 6 && error.code !== 'already-exists') {
        throw error;
      }
    });

  if (!created) {
    return { skipped: true, successCount: 0, failureCount: 0, tokenCount: 0 };
  }

  const push = await sendAdminPush(db, {
    title,
    body: content,
    data: {
      type: 'QR Code',
      actionType: 'qr_code',
      notificationTag: `qr_code_${tenantId}_${qrEvent}`,
      tenantId,
      qrEvent,
      expiresAt: expiresAt instanceof Date ? expiresAt.toISOString() : '',
      daysRemaining: daysRemaining == null ? '' : String(daysRemaining),
    },
  });

  await db.collection('notifications').doc(id).set({
    pushStatus: push.failureCount > 0 ? 'partial' : 'sent',
    pushSuccessCount: push.successCount,
    pushFailureCount: push.failureCount,
    pushTokenCount: push.tokenCount,
    pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  return { skipped: false, ...push };
}

async function runQrLifecycleCheck() {
  if (!initializeFirebaseAdmin()) {
    throw new Error('Firebase Admin not initialized. Check FIREBASE_SERVICE_ACCOUNT.');
  }

  const db = admin.firestore();
  const [tenantsSnap, tokenDocs, geoFenceRadius] = await Promise.all([
    db.collection('tenants').get(),
    db.collection('qr_tokens').get(),
    loadGeoFenceRadius(db),
  ]);
  const tokenMap = new Map(tokenDocs.docs.map((doc) => [doc.id, doc]));
  const tenantIds = new Set([
    ...tenantsSnap.docs.map((doc) => doc.id),
    ...tokenDocs.docs.map((doc) => doc.id),
  ]);
  const now = new Date();
  const todayKey = dateKeyFor(now);
  const nextExpiryDate = new Date(now.getTime() + 90 * 24 * 60 * 60 * 1000);

  let checked = 0;
  let refreshed = 0;
  let notificationsCreated = 0;
  let pushSuccessCount = 0;
  let pushFailureCount = 0;

  for (const tenantId of tenantIds) {
    checked += 1;
    const existing = tokenMap.get(tenantId);
    const data = existing && existing.exists ? existing.data() || {} : {};
    const expiresAt = data.expiresAt && data.expiresAt.toDate
      ? data.expiresAt.toDate()
      : null;
    const shouldRefresh = !(expiresAt instanceof Date) || expiresAt <= now;

    if (shouldRefresh) {
      const wasExpired = expiresAt instanceof Date && expiresAt <= now;
      if (wasExpired) {
        const result = await writeNotificationAndPush(db, {
          id: `qr_expired_${todayKey}_${tenantId}`,
          tenantId,
          title: 'QR Code Expired',
          content: 'Attendance QR code has expired. The system is refreshing it automatically.',
          qrEvent: 'expired',
          expiresAt,
          daysRemaining: 0,
        });
        if (!result.skipped) notificationsCreated += 1;
        pushSuccessCount += result.successCount;
        pushFailureCount += result.failureCount;
      }

      await db.collection('qr_tokens').doc(tenantId).set({
        token: generateToken(),
        expiresAt: admin.firestore.Timestamp.fromDate(nextExpiryDate),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        refreshedAt: admin.firestore.FieldValue.serverTimestamp(),
        tenantId,
        geoFenceRadius,
        refreshSource: 'vercel_auto',
        validForDays: 90,
      }, { merge: true });
      refreshed += 1;

      const result = await writeNotificationAndPush(db, {
        id: `qr_auto_refresh_${todayKey}_${tenantId}`,
        tenantId,
        title: wasExpired ? 'Expired QR Code Auto Refreshed' : 'QR Code Auto Generated',
        content: `Attendance QR code was automatically ${wasExpired ? 'refreshed after expiry' : 'generated'}. Valid until ${dateKeyFor(nextExpiryDate)}.`,
        qrEvent: 'auto_refresh',
        expiresAt: nextExpiryDate,
      });
      if (!result.skipped) notificationsCreated += 1;
      pushSuccessCount += result.successCount;
      pushFailureCount += result.failureCount;
      continue;
    }

    const remainingDays = daysUntilExpiry(now, expiresAt);
    if ([1, 2, 3].includes(remainingDays)) {
      const result = await writeNotificationAndPush(db, {
        id: `qr_expiry_${remainingDays}_${todayKey}_${tenantId}`,
        tenantId,
        title: `QR Code Expires in ${remainingDays} Day${remainingDays === 1 ? '' : 's'}`,
        content: `Attendance QR code will expire in ${remainingDays} day${remainingDays === 1 ? '' : 's'}.`,
        qrEvent: 'expiry_warning',
        expiresAt,
        daysRemaining: remainingDays,
      });
      if (!result.skipped) notificationsCreated += 1;
      pushSuccessCount += result.successCount;
      pushFailureCount += result.failureCount;
    }
  }

  return {
    checked,
    refreshed,
    notificationsCreated,
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

  const cronSecret = process.env.QR_CRON_SECRET || process.env.CRON_SECRET;
  if (cronSecret) {
    const bearer = String(req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const headerSecret = String(req.headers['x-cron-secret'] || '');
    if (bearer !== cronSecret && headerSecret !== cronSecret) {
      return res.status(401).json({ error: 'Unauthorized.' });
    }
  }

  try {
    const result = await runQrLifecycleCheck();
    return res.status(200).json({
      success: true,
      message: 'QR lifecycle check completed.',
      ...result,
    });
  } catch (error) {
    console.error('QR lifecycle check failed:', error);
    return res.status(500).json({
      error: 'QR lifecycle check failed.',
      details: error.message,
    });
  }
}
