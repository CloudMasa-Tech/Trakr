const admin = require('firebase-admin');

function initializeFirebaseAdmin() {
  if (admin.apps.length) return admin;

  try {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } catch (error) {
    console.error('Error initializing Firebase Admin:', error);
  }

  return admin;
}

module.exports = {
  admin,
  initializeFirebaseAdmin,
};
