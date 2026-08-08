const path = require('path');
const admin = require('firebase-admin');

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(__dirname, 'serviceAccountKey.json');

const PROJECT_ID = process.env.SUPERADMIN_PROJECT_ID || 'trakradminsetup-28437';
const ADMIN_EMAIL = process.env.SUPERADMIN_EMAIL || 'keerthana.s@cloudmasa.com';

admin.initializeApp({
  credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  projectId: PROJECT_ID,
});

const auth = admin.auth();
const firestore = admin.firestore();
const Timestamp = admin.firestore.FieldValue.serverTimestamp;

async function main() {
  const user = await auth.getUserByEmail(ADMIN_EMAIL);
  const uid = user.uid;
  console.log(`User found: ${user.email} (uid: ${uid})`);

  const updates = {
    role: 'super_admin',
    status: 'active',
    isActive: true,
    updatedAt: Timestamp(),
  };

  await firestore.collection('users').doc(uid).set(updates, { merge: true });
  console.log('users/{uid}  -> role: super_admin');

  await firestore.collection('admins').doc(uid).set(updates, { merge: true });
  console.log('admins/{uid} -> role: super_admin');

  await firestore
    .collection('app_config')
    .doc('admin_access')
    .set(
      {
        primaryAdminEmail: ADMIN_EMAIL,
        role: 'super_admin',
        updatedAt: Timestamp(),
      },
      { merge: true },
    );
  console.log('app_config/admin_access -> primaryAdminEmail kept');

  console.log('\nDone. keerthana.s@cloudmasa.com is now a Super Admin.');
  console.log('Sign out and sign back in to load the Super Admin dashboard.');
}

main().catch((e) => {
  console.error('Failed:', e);
  process.exit(1);
});
