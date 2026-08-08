// Platform-wide broadcast push used by the super-admin composer in
// `notifications_module.dart`.
const { admin, initializeFirebaseAdmin } = require('../lib/firebaseAdmin');
const {
  cleanNotificationText,
  collectAdminTokens,
  collectAllTokens,
  sendMulticast,
} = require('../lib/helpers');

export default async function handler(req, res) {
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
    const { title, body, recipient } = req.body || {};

    if (!title || !body) {
      return res.status(400).json({ error: 'Missing required fields: title and body.' });
    }

    if (!initializeFirebaseAdmin()) {
      return res.status(500).json({ error: 'Firebase Admin not initialized properly. Check environment variables.' });
    }

    const db = admin.firestore();
    const target = String(recipient || 'admin').trim().toLowerCase();
    const tokens = target === 'all'
      ? await collectAllTokens(db)
      : await collectAdminTokens(db);

    if (tokens.length === 0) {
      return res.status(404).json({ error: 'No FCM token found for the broadcast recipient.' });
    }

    const displayTitle = cleanNotificationText(title);
    const displayBody = cleanNotificationText(body);
    const push = await sendMulticast(tokens, {
      title: displayTitle,
      body: displayBody,
      data: {
        type: 'broadcast',
        notificationFormat: 'dynamic',
        notificationTitle: displayTitle,
        notificationBody: displayBody,
        notificationTag: `broadcast_${Date.now()}`,
      },
    });

    return res.status(200).json({
      success: true,
      message: 'Broadcast notification sent successfully.',
      ...push,
    });
  } catch (error) {
    console.error('Error sending broadcast notification:', error);
    return res.status(500).json({ error: 'Internal server error', details: error.message });
  }
}
