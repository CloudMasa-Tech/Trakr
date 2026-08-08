const admin = require('firebase-admin');

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
  let cleaned = removeBrandText(value)
    .replace(/\bstaff\s+check[\s\u2010-\u2015-]*out\s+recorded\b/gi, 'Work Session Closed')
    .replace(/\bstaff\s+check[\s\u2010-\u2015-]*in\s+recorded\b/gi, 'Secure Check-In');

  cleaned = cleaned.replace(
    /^(?:(?:📍|⚠️)\s*)?(?:staff members?\s+)?(.+?)\s+(?:has\s+)?checked\s+in(?:\s+successfully)?\.\s*status:\s*late\.?$/i,
    '⚠️ $1 checked in late',
  );

  cleaned = cleaned.replace(
    /^(?:👋\s*)?(?:staff members?\s+)?(.+?)\s+(?:has\s+)?checked\s+out(?:\s+successfully|\.\s*status:\s*[^.]+)?\.?$/i,
    '👋 $1 checked out',
  );

  return cleaned
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

function attendanceNotificationBody(body, data, matchedProfiles) {
  const isActorDevice = Array.isArray(matchedProfiles) &&
    matchedProfiles.some((profile) => profileMatchesActor(profile, data));
  if (!isActorDevice) {
    return valueOf(data, 'attendanceAction')
      ? managerAttendanceNotificationBody(body, data)
      : cleanNotificationText(body);
  }

  switch (data && data.attendanceAction) {
    case 'check-in':
      return 'Your attendance has been recorded successfully.';
    case 'check-out':
      return 'Your work session has been completed successfully.';
    case 'temporary exit':
      return 'Your temporary exit has been registered successfully.';
    case 're-entry':
      return 'Welcome Back, Your re-entry has been recorded successfully.';
    case 'late check-in':
      return data.attendanceDetail === undefined || data.attendanceDetail === null
        ? cleanNotificationText(body)
        : `Your attendance has been recorded successfully. You are late by ${data.attendanceDetail} minutes.`;
    case 'absent':
    case 'missing-check-in':
      return '📌 No check-in activity detected today.';
    default:
      return cleanNotificationText(body);
  }
}

function managerAttendanceNotificationBody(body, data) {
  const action = valueOf(data, 'attendanceAction').toLowerCase();
  const name = valueOf(data, 'employeeName') || 'Employee';
  const detail = valueOf(data, 'attendanceDetail');

  switch (action) {
    case 'check-in':
      return `📍 ${name} checked in successfully.`;
    case 'late check-in':
      return detail
        ? `⚠️ ${name} checked in late. Late by ${detail} minutes.`
        : `⚠️ ${name} checked in late.`;
    case 'check-out':
      return `👋 ${name} checked out successfully`;
    case 'early check-out':
    case 'early checkout':
    case 'early-checkout':
      return `⚠️ ${name} checked out early. Please review the attendance log.`;
    case 'missing-check-in':
    case 'absent':
      return `📌 ${name} has no check-in activity today. Status: absent.`;
    default:
      return cleanNotificationText(body);
  }
}

function fcmDataPayload(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    return undefined;
  }

  return Object.entries(data).reduce((payload, [key, value]) => {
    if (value === undefined || value === null) return payload;
    payload[key] =
      typeof value === 'string' ? value : JSON.stringify(value);
    return payload;
  }, {});
}

function addTokensFromDoc(tokens, data) {
  if (data && typeof data.fcmToken === 'string' && data.fcmToken.trim()) {
    tokens.add(data.fcmToken.trim());
  }
  if (data && Array.isArray(data.fcmTokens)) {
    data.fcmTokens.forEach((token) => {
      if (typeof token === 'string' && token.trim()) tokens.add(token.trim());
    });
  }
}

function valueOf(data, key) {
  const value = data && data[key];
  return value === undefined || value === null ? '' : String(value).trim();
}

function pushNotificationTag(data) {
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

  return '';
}

function sameText(left, right) {
  return String(left || '').trim().toLowerCase() ===
    String(right || '').trim().toLowerCase();
}

function phoneLookupCandidates(phone) {
  const trimmed = String(phone || '').trim();
  const compact = trimmed.replace(/\s+/g, '');
  const digitsOnly = trimmed.replace(/[^0-9+]/g, '');
  const withoutPlusCountry = digitsOnly.replace(/^\+?91/, '');
  return Array.from(new Set([
    trimmed,
    compact,
    digitsOnly,
    withoutPlusCountry,
    withoutPlusCountry ? `+91${withoutPlusCountry}` : '',
    withoutPlusCountry ? `+91 ${withoutPlusCountry}` : '',
    withoutPlusCountry ? `91${withoutPlusCountry}` : '',
  ].filter(Boolean)));
}

function isEarlyCheckoutNotification(data, body) {
  const action = valueOf(data, 'attendanceAction').toLowerCase();
  return action === 'early check-out' ||
    action === 'early checkout' ||
    action === 'early-checkout' ||
    /\bearly\s+check[\s\u2010-\u2015-]*out\b/i.test(String(body || ''));
}

function isDynamicNotification(data) {
  const format = valueOf(data, 'notificationFormat').toLowerCase();
  return format === 'dynamic' ||
    Boolean(valueOf(data, 'notificationTitle')) ||
    Boolean(valueOf(data, 'notificationBody')) ||
    !Boolean(valueOf(data, 'attendanceAction'));
}

function isActionableRequest(data) {
  const actionType = valueOf(data, 'actionType');
  return Boolean(valueOf(data, 'requestId')) &&
    ['leave_request', 'permission_request', 'checkout_request'].includes(actionType);
}

function dynamicNotificationDisplay(title, body, data) {
  if (isDynamicNotification(data)) {
    return {
      title: removeBrandPrefix(removeBrandText(
        valueOf(data, 'notificationTitle') || String(title || '').trim(),
      )),
      body: removeBrandText(
        valueOf(data, 'notificationBody') || String(body || '').trim(),
      ),
    };
  }

  return {
    title: cleanNotificationTitle(title, body),
    body: attendanceNotificationBody(body, data, []),
  };
}

function profileMatchesActor(profile, data) {
  const employeeId = valueOf(data, 'employeeId');
  const employeeName = valueOf(data, 'employeeName');
  const profileData = profile.data || {};

  return (employeeId &&
      (sameText(profile.id, employeeId) ||
        sameText(profileData.employeeId, employeeId) ||
        sameText(profileData.uid, employeeId))) ||
    (employeeName && sameText(profileData.name, employeeName));
}

async function addTokensFromCollection(db, collectionName, tokens) {
  const snap = await db.collection(collectionName).get();
  snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
}

function addMatchedProfile(matchedProfiles, seenProfiles, collectionName, doc, tokens) {
  const key = `${collectionName}/${doc.id}`;
  if (seenProfiles.has(key)) return;
  seenProfiles.add(key);

  const profileData = doc.data();
  matchedProfiles.push({ collectionName, id: doc.id, data: profileData });
  addTokensFromDoc(tokens, profileData);
}

async function addProfilesByPhone(db, phone, matchedProfiles, seenProfiles, tokens) {
  const phoneCandidates = phoneLookupCandidates(phone);
  if (phoneCandidates.length === 0) return;

  const collections = ['users', 'staff', 'managers', 'admins'];
  const queries = [];

  for (const collectionName of collections) {
    for (const phoneCandidate of phoneCandidates) {
      queries.push(
        db.collection(collectionName)
          .where('phone', '==', phoneCandidate)
          .limit(10)
          .get()
          .then((snap) => {
            snap.forEach((doc) => addMatchedProfile(
              matchedProfiles,
              seenProfiles,
              collectionName,
              doc,
              tokens,
            ));
          }),
      );
    }
  }

  await Promise.all(queries);
}

async function addProfilesByIdentifier(db, identifier, matchedProfiles, seenProfiles, tokens) {
  const value = String(identifier || '').trim();
  if (!value) return;

  const collections = ['users', 'staff', 'managers', 'admins'];
  const lowerValue = value.toLowerCase();
  const queries = [];

  for (const collectionName of collections) {
    const collection = db.collection(collectionName);
    queries.push(
      collection.doc(value).get().then((doc) => {
        if (doc.exists) {
          addMatchedProfile(matchedProfiles, seenProfiles, collectionName, doc, tokens);
        }
      }),
    );

    for (const [field, lookupValue] of [
      ['employeeId', value],
      ['email', value],
      ['email', lowerValue],
      ['name', value],
      ['phone', value],
    ]) {
      queries.push(
        collection.where(field, '==', lookupValue)
          .limit(10)
          .get()
          .then((snap) => {
            snap.forEach((doc) => addMatchedProfile(
              matchedProfiles,
              seenProfiles,
              collectionName,
              doc,
              tokens,
            ));
          }),
      );
    }
  }

  await Promise.all(queries);
}

async function addRoleTokens(db, role, tokens) {
  const cleanRole = String(role || '').trim().toLowerCase();
  if (!cleanRole) return;

  if (cleanRole === 'admin') {
    await Promise.all([
      addTokensFromCollection(db, 'admins', tokens),
      db.collection('users')
        .where('role', '==', 'admin')
        .limit(100)
        .get()
        .then((snap) => snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()))),
    ]);
    return;
  }

  if (cleanRole === 'manager') {
    await Promise.all([
      addTokensFromCollection(db, 'managers', tokens),
      db.collection('users')
        .where('role', '==', 'manager')
        .limit(100)
        .get()
        .then((snap) => snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()))),
    ]);
  }
}

async function addManagerTokens(db, managerName, tokens) {
  const cleanManagerName = String(managerName || '').trim();
  if (!cleanManagerName) return;

  const doc = await db.collection('managers').doc(cleanManagerName).get();
  if (doc.exists) addTokensFromDoc(tokens, doc.data());

  for (const field of ['name', 'email', 'employeeId']) {
    const snap = await db
      .collection('managers')
      .where(field, '==', cleanManagerName)
      .limit(5)
      .get();
    snap.forEach((managerDoc) => addTokensFromDoc(tokens, managerDoc.data()));
  }
}

function relatedProfileKeys(profile) {
  const data = profile && profile.data ? profile.data : {};
  return {
    ids: Array.from(new Set([
      profile && profile.id,
      valueOf(data, 'uid'),
      valueOf(data, 'userId'),
      valueOf(data, 'staffId'),
      valueOf(data, 'employeeId'),
    ].filter(Boolean))),
    emails: Array.from(new Set([
      valueOf(data, 'email'),
      valueOf(data, 'email').toLowerCase(),
    ].filter(Boolean))),
    names: Array.from(new Set([
      valueOf(data, 'name'),
      valueOf(data, 'employeeName'),
      valueOf(data, 'userName'),
    ].filter(Boolean))),
  };
}

async function addTokensFromRelatedProfiles(db, tokens, matchedProfiles) {
  const collections = ['users', 'staff', 'managers', 'admins'];
  const queries = [];

  for (const profile of matchedProfiles) {
    const keys = relatedProfileKeys(profile);

    for (const collectionName of collections) {
      for (const id of keys.ids) {
        queries.push(
          db.collection(collectionName).doc(id).get().then((doc) => {
            if (doc.exists) addTokensFromDoc(tokens, doc.data());
          }),
        );
      }

      for (const email of keys.emails) {
        queries.push(
          db.collection(collectionName)
            .where('email', '==', email)
            .limit(5)
            .get()
            .then((snap) => {
              snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
            }),
        );
      }

      for (const employeeId of keys.ids) {
        queries.push(
          db.collection(collectionName)
            .where('employeeId', '==', employeeId)
            .limit(5)
            .get()
            .then((snap) => {
              snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
            }),
        );
      }

      for (const name of keys.names) {
        queries.push(
          db.collection(collectionName)
            .where('name', '==', name)
            .limit(5)
            .get()
            .then((snap) => {
              snap.forEach((doc) => addTokensFromDoc(tokens, doc.data()));
            }),
        );
      }
    }
  }

  await Promise.all(queries);
}

async function addEarlyCheckoutEscalationTokens(db, tokens, data, matchedProfiles) {
  if (!matchedProfiles.some((profile) => profileMatchesActor(profile, data))) {
    return;
  }

  const actorIsManager = matchedProfiles.some((profile) => {
    const role = valueOf(profile.data, 'role').toLowerCase();
    return profile.collectionName === 'managers' || role === 'manager';
  });

  await addTokensFromCollection(db, 'admins', tokens);

  if (!actorIsManager) {
    await addManagerTokens(db, valueOf(data, 'managerName'), tokens);
  }
}

// Initialize Firebase Admin only once
if (!admin.apps.length) {
  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
  } catch (error) {
    console.error('Error parsing FIREBASE_SERVICE_ACCOUNT from env:', error);
  }
}

export default async function handler(req, res) {
  // Allow CORS
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,PATCH,DELETE,POST,PUT');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed. Use POST.' });
  }

  try {
    const { phone, identifier, role, title, body, data } = req.body;

    if ((!phone && !identifier && !role) || !title || !body) {
      return res.status(400).json({ error: 'Missing required fields: phone, identifier, or role; plus title and body.' });
    }

    if (!admin.apps.length) {
      return res.status(500).json({ error: 'Firebase Admin not initialized properly. Check environment variables.' });
    }

    const db = admin.firestore();
    const tokens = new Set();
    const matchedProfiles = [];
    const seenProfiles = new Set();

    await Promise.all([
      addRoleTokens(db, role, tokens),
      addProfilesByIdentifier(db, identifier, matchedProfiles, seenProfiles, tokens),
      addProfilesByPhone(db, phone, matchedProfiles, seenProfiles, tokens),
    ]);

    await addTokensFromRelatedProfiles(db, tokens, matchedProfiles);

    if (isEarlyCheckoutNotification(data, body)) {
      await addEarlyCheckoutEscalationTokens(db, tokens, data, matchedProfiles);
    }

    const tokenArray = Array.from(tokens);

    if (tokenArray.length === 0) {
      return res.status(404).json({ error: 'No FCM token found for the provided recipient.' });
    }

    const display = isDynamicNotification(data)
      ? dynamicNotificationDisplay(title, body, data)
      : {
          body: attendanceNotificationBody(body, data, matchedProfiles),
          title: null,
        };
    if (!display.title) {
      display.title = cleanNotificationTitle(title, display.body);
    }
    const notificationTag = pushNotificationTag(data);
    const messageData = {
      ...(fcmDataPayload(data) || {}),
      title: String(display.title),
      body: String(display.body),
      ...(notificationTag ? { notificationTag } : {}),
    };
    const actionableRequest = isActionableRequest(data);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokenArray,
      ...(actionableRequest ? {} : { notification: {
        title: String(display.title),
        body: String(display.body),
      } }),
      data: messageData,
      android: {
        priority: 'high',
        ...(notificationTag ? { collapseKey: notificationTag } : {}),
        ...(actionableRequest ? {} : { notification: {
          channelId: 'high_importance_channel',
          ...(notificationTag ? { tag: notificationTag } : {}),
          priority: 'max',
          sound: 'default',
          defaultSound: true,
          visibility: 'public',
        } }),
      },
      apns: {
        headers: {
          'apns-priority': '10',
        },
        payload: {
          aps: {
            alert: {
              title: String(display.title),
              body: String(display.body),
            },
            sound: 'default',
          },
        },
      },
      webpush: {
        notification: {
          title: String(display.title),
          body: String(display.body),
          ...(notificationTag ? { tag: notificationTag } : {}),
        },
      },
    });

    return res.status(200).json({
      success: true,
      message: 'Push notification sent successfully.',
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

  } catch (error) {
    console.error('Error sending push notification:', error);
    return res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}
