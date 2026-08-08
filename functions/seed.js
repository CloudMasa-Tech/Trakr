const path = require('path');
const admin = require('firebase-admin');

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  path.join(__dirname, 'serviceAccountKey.json');

// Credentials are supplied via environment variables — never hardcoded.
const ADMIN_EMAIL = process.env.SUPERADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.SUPERADMIN_PASSWORD;
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  console.error('Please set SUPERADMIN_EMAIL and SUPERADMIN_PASSWORD before seeding.');
  console.error('  export SUPERADMIN_EMAIL=admin@example.com');
  console.error('  export SUPERADMIN_PASSWORD=change-me');
  process.exit(1);
}
const ADMIN_NAME = process.env.SUPERADMIN_NAME || 'Platform Administrator';
const PROJECT_ID = process.env.SUPERADMIN_PROJECT_ID || 'trakradminsetup-28437';
const ADMIN_ROLE = 'super_admin';

admin.initializeApp({
  credential: admin.credential.cert(require(SERVICE_ACCOUNT_PATH)),
  projectId: PROJECT_ID,
});

const auth = admin.auth();
const firestore = admin.firestore();
const Timestamp = admin.firestore.FieldValue.serverTimestamp;

const DEFAULT_PERMISSIONS = [
  { id: 'attendance.view_own', name: 'View Own Attendance', category: 'attendance' },
  { id: 'attendance.view_team', name: 'View Team Attendance', category: 'attendance' },
  { id: 'attendance.view_all', name: 'View All Attendance', category: 'attendance' },
  { id: 'attendance.check_in_out', name: 'Check In/Out', category: 'attendance' },
  { id: 'team.view', name: 'View Team', category: 'team' },
  { id: 'team.manage', name: 'Manage Team', category: 'team' },
  { id: 'leave.apply', name: 'Apply Leave', category: 'leave' },
  { id: 'leave.approve', name: 'Approve Leave', category: 'leave' },
  { id: 'permission.apply', name: 'Request Permission', category: 'permission' },
  { id: 'permission.approve', name: 'Approve Permission', category: 'permission' },
  { id: 'reports.view', name: 'View Reports', category: 'reports' },
  { id: 'payroll.view', name: 'View Payroll', category: 'payroll' },
  { id: 'payroll.manage', name: 'Manage Payroll', category: 'payroll' },
  { id: 'users.manage', name: 'Manage Users', category: 'users' },
  { id: 'company.settings', name: 'Company Settings', category: 'company' },
  { id: 'holidays.manage', name: 'Manage Holidays', category: 'company' },
  { id: 'notifications.send', name: 'Send Notifications', category: 'notifications' },
  { id: 'geo.manage', name: 'Manage Geofence', category: 'company' },
];

const DEFAULT_PLANS = [
  {
    id: 'free',
    name: 'Free',
    description: 'Up to 10 employees with core QR attendance.',
    monthlyPrice: 0,
    annualPrice: 0,
    maxSeats: 10,
    features: { qr: true, geofence: true, reports: false, payroll: false, api: false },
  },
  {
    id: 'starter',
    name: 'Starter',
    description: 'Up to 50 employees with reports and support.',
    monthlyPrice: 49,
    annualPrice: 470,
    maxSeats: 50,
    features: { qr: true, geofence: true, reports: true, payroll: false, api: false },
  },
  {
    id: 'pro',
    name: 'Pro',
    description: 'Up to 250 employees, payroll and priority support.',
    monthlyPrice: 149,
    annualPrice: 1429,
    maxSeats: 250,
    features: { qr: true, geofence: true, reports: true, payroll: true, api: false },
  },
  {
    id: 'enterprise',
    name: 'Enterprise',
    description: 'Unlimited seats, SSO, API access and dedicated support.',
    monthlyPrice: 499,
    annualPrice: 4790,
    maxSeats: 0,
    features: { qr: true, geofence: true, reports: true, payroll: true, api: true },
  },
];

// Web credentials of the project this script seeds. Public (client SDK) values,
// kept in sync with lib/firebase_options.dart + web/firebase-messaging-sw.js.
const PROJECT_WEB_CONFIG = {
  apiKey: 'AIzaSyDqH4PCc-rs86qYI5ZGwi2WOU4PtMJJzVE',
  appId: '1:6848613159:web:3250e45472fa6762137702',
  messagingSenderId: '6848613159',
  projectId: PROJECT_ID,
  authDomain: `${PROJECT_ID}.firebaseapp.com`,
  measurementId: 'G-N3M010CSJ9',
};

async function createUser() {
  try {
    const user = await auth.getUserByEmail(ADMIN_EMAIL);
    console.log(`User already exists: ${user.uid}`);
    return user;
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const user = await auth.createUser({
        email: ADMIN_EMAIL,
        password: ADMIN_PASSWORD,
        displayName: ADMIN_NAME,
        emailVerified: true,
      });
      console.log(`Created user: ${user.uid}`);
      return user;
    }
    throw e;
  }
}

async function seedPermissions() {
  const batch = firestore.batch();
  for (const perm of DEFAULT_PERMISSIONS) {
    const ref = firestore.collection('permissions').doc(perm.id);
    batch.set(ref, {
      name: perm.name,
      description: '',
      category: perm.category,
      isSystem: true,
      createdAt: Timestamp(),
    }, { merge: true });
  }
  await batch.commit();
  console.log(`Seeded ${DEFAULT_PERMISSIONS.length} permissions`);
}

async function seedPlans() {
  const batch = firestore.batch();
  for (const plan of DEFAULT_PLANS) {
    const { id, ...data } = plan;
    batch.set(firestore.collection('plans').doc(id), {
      ...data,
      isActive: true,
      createdAt: Timestamp(),
      updatedAt: Timestamp(),
    }, { merge: true });
  }
  await batch.commit();
  console.log(`Seeded ${DEFAULT_PLANS.length} plans`);
}

async function seedAllocationPool() {
  const ref = firestore.collection('firebase_project_allocations').doc(PROJECT_ID);
  await ref.set({
    projectId: PROJECT_ID,
    firebaseConfig: PROJECT_WEB_CONFIG,
    status: 'available',
    label: 'Primary (current) project',
    createdAt: Timestamp(),
    updatedAt: Timestamp(),
  }, { merge: true });
  console.log(`Allocation pool: ${PROJECT_ID} available`);
}

async function seed(uid) {
  const companyName = 'Cloudmasa Attendances';
  const companyRef = firestore.collection('companies').doc();
  const companyId = companyRef.id;
  const allPermissionIds = DEFAULT_PERMISSIONS.map(p => p.id);

  const batch = firestore.batch();

  // Company
  batch.set(companyRef, {
    name: companyName,
    domain: 'cloudmasa.com',
    primaryColorHex: '0F766E',
    logoUrl: null,
    supportEmail: ADMIN_EMAIL,
    isActive: true,
    createdAt: Timestamp(),
    updatedAt: Timestamp(),
  });
  console.log(`Company: ${companyId}`);

  // Admin doc (admins collection)
  batch.set(firestore.collection('admins').doc(uid), {
    name: ADMIN_NAME,
    email: ADMIN_EMAIL,
    authUid: uid,
    role: ADMIN_ROLE,
    status: 'active',
    isActive: true,
    photoUrl: null,
    companyId,
    designation: 'Super Administrator',
    permissionIds: allPermissionIds,
    updatedAt: Timestamp(),
    createdAt: Timestamp(),
    source: 'seed_script',
  });

  // User doc (users collection)
  batch.set(firestore.collection('users').doc(uid), {
    name: ADMIN_NAME,
    email: ADMIN_EMAIL,
    role: ADMIN_ROLE,
    designation: 'Super Administrator',
    companyId,
    permissionIds: allPermissionIds,
    updatedAt: Timestamp(),
    createdAt: Timestamp(),
  });

  // White-label settings
  batch.set(firestore.collection('settings').doc('white_label'), {
    companyName,
    primaryColorHex: '0F766E',
    supportEmail: ADMIN_EMAIL,
    updatedAt: Timestamp(),
  }, { merge: true });

  // App config
  batch.set(firestore.collection('app_config').doc('admin_access'), {
    primaryAdminEmail: ADMIN_EMAIL,
    updatedAt: Timestamp(),
  }, { merge: true });

  // Geo config + Office
  const geoData = {
    name: 'Cloudmasa Office',
    companyId,
    latitude: null,
    longitude: null,
    radius: 50,
    geoFenceRadius: 50,
    checkInStart: '08:30 AM',
    checkInEnd: '10:30 AM',
    checkOutEnd: '07:30 PM',
    updatedAt: Timestamp(),
  };
  batch.set(firestore.collection('geo_config').doc('default'), geoData, { merge: true });
  batch.set(firestore.collection('offices').doc('default'), geoData, { merge: true });

  // QR token placeholder
  batch.set(firestore.collection('qr_tokens').doc('initial'), {
    info: 'Initialized by admin setup',
    tenantId: companyId,
    createdAt: Timestamp(),
  }, { merge: true });

  // Attendance alert marker
  batch.set(firestore.collection('attendance_alerts').doc('system_init'), {
    message: 'System initialized by Keerthana S',
    type: 'info',
    createdAt: Timestamp(),
  }, { merge: true });

  // Workspace registry entry (control plane) so the seeded company shows up in
  // the Super Admin portal with the same shape as freshly onboarded workspaces.
  const workspaceRef = firestore.collection('workspaces').doc();
  batch.set(workspaceRef, {
    workspaceId: workspaceRef.id,
    workspaceCode: 'cloudmasa',
    companyName,
    firebaseProjectId: PROJECT_ID,
    firebaseConfig: PROJECT_WEB_CONFIG,
    status: 'active',
    onboardingStatus: 'complete',
    subscription: {
      planId: 'free',
      planName: 'Free',
      status: 'trialing',
      billingCycle: 'monthly',
      price: 0,
      currency: 'USD',
      seats: 0,
      startedAt: Timestamp(),
      createdAt: Timestamp(),
      updatedAt: Timestamp(),
    },
    supportEmail: ADMIN_EMAIL,
    createdAt: Timestamp(),
    updatedAt: Timestamp(),
  });
  console.log(`Workspace: ${workspaceRef.id} (code: cloudmasa)`);

  await batch.commit();
  console.log('Firestore seed documents written');
}

async function main() {
  try {
    const user = await createUser();
    await seedPermissions();
    await seedPlans();
    await seedAllocationPool();
    await seed(user.uid);
    console.log('\n=== SEED COMPLETE ===');
    console.log('Project:  ' + PROJECT_ID);
    console.log('Email:    ' + ADMIN_EMAIL);
    console.log('Role:     ' + ADMIN_ROLE);
    console.log('Company:  Cloudmasa Attendances');
    console.log('\nYou can now run: flutter run -d chrome');
    process.exit(0);
  } catch (e) {
    console.error('Seed failed:', e);
    process.exit(1);
  }
}

main();
