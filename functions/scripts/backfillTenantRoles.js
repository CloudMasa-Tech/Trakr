#!/usr/bin/env node

const admin = require('firebase-admin');

function parseArgs(argv) {
  const options = {
    dryRun: false,
    project: '',
  };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === '--dry-run') options.dryRun = true;
    if (argv[i] === '--project' && argv[i + 1]) {
      options.project = argv[i + 1];
      i++;
    }
  }
  return options;
}

const options = parseArgs(process.argv);
const MASTER_PROJECT_ID = options.project || 'trakradminsetup-28437';
const DRY_RUN = options.dryRun;

if (admin.apps.length === 0) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: MASTER_PROJECT_ID,
  });
}

async function main() {
  console.log(`Starting Tenant Roles Backfill (canBeReportingManager)`);
  console.log(`Master Project: ${MASTER_PROJECT_ID}`);
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN' : 'EXECUTE'}\n`);

  const masterDb = admin.firestore();
  const workspacesSnap = await masterDb.collection('workspaces').get();
  console.log(`Found ${workspacesSnap.docs.length} workspaces.\n`);

  let affectedTenants = 0;
  let updatedRolesCount = 0;

  for (const doc of workspacesSnap.docs) {
    const data = doc.data() || {};
    const workspaceId = doc.id;
    const config = data.firebaseConfig || {};
    const tenantProjectId = config.projectId;
    const companyName = data.companyName || 'Unknown';

    if (!tenantProjectId) {
      console.log(`⚠️  Skipping ${workspaceId} (${companyName}) - No firebaseConfig.projectId found.`);
      continue;
    }

    console.log(`Inspecting tenant: ${companyName} (${workspaceId} / ${tenantProjectId})`);

    // Initialize secondary app
    const appName = `tenant_${workspaceId}`;
    let tenantApp;
    try {
      tenantApp = admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: tenantProjectId,
      }, appName);

      const tenantDb = tenantApp.firestore();
      
      const rolesToUpdate = ['company_admin', 'manager'];
      let tenantNeededUpdate = false;

      for (const roleId of rolesToUpdate) {
        const roleRef = tenantDb.collection('roles').doc(roleId);
        const roleSnap = await roleRef.get();

        if (roleSnap.exists) {
          const roleData = roleSnap.data();
          if (roleData.canBeReportingManager === undefined) {
            console.log(`   - Found missing canBeReportingManager on roles/${roleId}`);
            tenantNeededUpdate = true;
            updatedRolesCount++;

            if (!DRY_RUN) {
              await roleRef.update({
                canBeReportingManager: true,
                updatedAt: admin.firestore.FieldValue.serverTimestamp()
              });
              console.log(`   ✅ Updated roles/${roleId} with canBeReportingManager: true`);
            }
          } else {
            console.log(`   - roles/${roleId} already has canBeReportingManager: ${roleData.canBeReportingManager}`);
          }
        } else {
          console.log(`   - roles/${roleId} does not exist in this tenant.`);
        }
      }

      if (tenantNeededUpdate) affectedTenants++;

    } catch (e) {
      console.error(`❌ Error processing tenant ${workspaceId}: ${e.message}`);
    } finally {
      if (tenantApp) {
        await tenantApp.delete();
      }
    }
  }

  console.log(`\n================================`);
  console.log(`Summary:`);
  console.log(`Affected Tenants: ${affectedTenants}`);
  if (!DRY_RUN) {
    console.log(`Total Roles Updated: ${updatedRolesCount}`);
  } else {
    console.log(`Total Roles That Would Be Updated: ${updatedRolesCount}`);
  }
  console.log(`================================`);
}

main().catch(console.error);
