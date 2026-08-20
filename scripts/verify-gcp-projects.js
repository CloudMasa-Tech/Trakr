#!/usr/bin/env node
/**
 * GCP Project Verification Cleanup Script
 * 
 * Scans all workspaces in the master Firestore, checks if each firebaseProjectId
 * actually exists in GCP via Cloud Resource Manager API projects.get, and reports
 * any workspace with no matching real GCP project.
 * 
 * Usage:
 *   node scripts/verify-gcp-projects.js [--fix] [--project <master-project-id>]
 * 
 * Options:
 *   --fix              Update workspace documents with verification results
 *   --project <id>     Master Firebase project ID (default: from GOOGLE_CLOUD_PROJECT env)
 *   --dry-run          Show what would be done without making changes
 *   --help             Show this help
 */

const admin = require('firebase-admin');
const { GoogleAuth } = require('google-auth-library');
const { program } = require('commander');

program
  .name('verify-gcp-projects')
  .description('Verify GCP projects for all workspaces in Firestore')
  .option('--fix', 'Update workspace documents with verification results')
  .option('-p, --project <id>', 'Master Firebase project ID')
  .option('--dry-run', 'Show what would be done without making changes')
  .option('-v, --verbose', 'Verbose output')
  .parse(process.argv);

const options = program.opts();

const MASTER_PROJECT_ID = options.project || process.env.GOOGLE_CLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
const DRY_RUN = options.dryRun || false;
const SHOULD_FIX = options.fix || false;
const VERBOSE = options.verbose || false;

if (!MASTER_PROJECT_ID) {
  console.error('ERROR: Master project ID not provided. Use --project <id> or set GOOGLE_CLOUD_PROJECT env var.');
  process.exit(1);
}

async function initializeFirebase() {
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: MASTER_PROJECT_ID,
    });
  }
  return admin.firestore();
}

async function getAccessToken() {
  const auth = new GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const token = await client.getAccessToken();
  return token.token;
}

async function checkGcpProjectExists(projectId, accessToken) {
  const url = `https://cloudresourcemanager.googleapis.com/v3/projects/${projectId}`;
  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    });

    if (response.ok) {
      const project = await response.json();
      return {
        exists: true,
        projectNumber: project.projectNumber,
        projectName: project.name,
        displayName: project.displayName,
        state: project.state,
        createTime: project.createTime,
      };
    } else if (response.status === 404) {
      return { exists: false, reason: 'NOT_FOUND' };
    } else if (response.status === 403) {
      return { exists: false, reason: 'PERMISSION_DENIED' };
    } else {
      const errorText = await response.text();
      return { exists: false, reason: `HTTP_${response.status}`, error: errorText };
    }
  } catch (error) {
    return { exists: false, reason: 'NETWORK_ERROR', error: error.message };
  }
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  GCP Project Verification for TRAKR Workspaces               ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log(`Master Project: ${MASTER_PROJECT_ID}`);
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no changes)' : (SHOULD_FIX ? 'FIX (will update Firestore)' : 'REPORT ONLY')}`);
  console.log('');

  const db = await initializeFirebase();
  const accessToken = await getAccessToken();

  console.log('Fetching all workspaces from Firestore...');
  const workspacesSnapshot = await db.collection('workspaces').get();
  console.log(`Found ${workspacesSnapshot.docs.length} workspaces.`);

  if (workspacesSnapshot.docs.length === 0) {
    console.log('No workspaces to verify.');
    return;
  }

  const results = {
    verified: [],
    unverified: [],
    missing: [],
    errors: [],
  };

  console.log('\nVerifying GCP projects...\n');

  for (const doc of workspacesSnapshot.docs) {
    const data = doc.data();
    const workspaceId = doc.id;
    const companyName = data.companyName || 'Unknown';
    const workspaceCode = data.workspaceCode || 'N/A';
    const firebaseProjectId = data.firebaseProjectId;
    const gcpProjectVerified = data.gcpProjectVerified === true;
    const gcpProjectNumber = data.gcpProjectNumber || null;

    if (!firebaseProjectId) {
      console.log(`  ⚠️  ${companyName} (${workspaceCode}) - NO FIREBASE PROJECT ID`);
      results.errors.push({
        workspaceId,
        companyName,
        workspaceCode,
        reason: 'NO_FIREBASE_PROJECT_ID',
      });
      continue;
    }

    if (VERBOSE) {
      console.log(`  Checking ${firebaseProjectId} (${companyName})...`);
    }

    const checkResult = await checkGcpProjectExists(firebaseProjectId, accessToken);

    if (checkResult.exists) {
      const isVerified = gcpProjectVerified && gcpProjectNumber === String(checkResult.projectNumber);
      
      if (isVerified) {
        console.log(`  ✅ ${companyName} (${workspaceCode}) - GCP Verified (Project: ${checkResult.projectNumber})`);
        results.verified.push({
          workspaceId,
          companyName,
          workspaceCode,
          firebaseProjectId,
          projectNumber: checkResult.projectNumber,
        });
      } else {
        console.log(`  ⚠️  ${companyName} (${workspaceCode}) - Project exists but NOT verified in Firestore (Project: ${checkResult.projectNumber})`);
        results.unverified.push({
          workspaceId,
          companyName,
          workspaceCode,
          firebaseProjectId,
          projectNumber: checkResult.projectNumber,
          currentVerified: gcpProjectVerified,
          currentProjectNumber: gcpProjectNumber,
        });

        if (SHOULD_FIX && !DRY_RUN) {
          await db.collection('workspaces').doc(workspaceId).update({
            gcpProjectVerified: true,
            gcpProjectNumber: String(checkResult.projectNumber),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`     → Updated workspace document`);
        }
      }
    } else {
      console.log(`  ❌ ${companyName} (${workspaceCode}) - GCP Project MISSING (${checkResult.reason})`);
      results.missing.push({
        workspaceId,
        companyName,
        workspaceCode,
        firebaseProjectId,
        reason: checkResult.reason,
        error: checkResult.error,
        currentVerified: gcpProjectVerified,
        currentProjectNumber: gcpProjectNumber,
      });

      if (SHOULD_FIX && !DRY_RUN) {
        await db.collection('workspaces').doc(workspaceId).update({
          gcpProjectVerified: false,
          gcpProjectNumber: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`     → Marked as unverified in Firestore`);
      }
    }

    // Small delay to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 100));
  }

  // Summary
  console.log('\n══════════════════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('══════════════════════════════════════════════════════════════');
  console.log(`Total workspaces:      ${workspacesSnapshot.docs.length}`);
  console.log(`✅ Verified:           ${results.verified.length}`);
  console.log(`⚠️  Exists but unverified: ${results.unverified.length}`);
  console.log(`❌ Missing in GCP:     ${results.missing.length}`);
  console.log(`⚠️  Errors/No config:  ${results.errors.length}`);

  if (results.missing.length > 0) {
    console.log('\n⚠️  PHANTOM WORKSPACES (GCP project does not exist):');
    for (const w of results.missing) {
      console.log(`   - ${w.companyName} (${w.workspaceCode}) - Project ID: ${w.firebaseProjectId} - Reason: ${w.reason}`);
    }
  }

  if (results.unverified.length > 0) {
    console.log('\n⚠️  UNVERIFIED WORKSPACES (GCP project exists but not marked in Firestore):');
    for (const w of results.unverified) {
      console.log(`   - ${w.companyName} (${w.workspaceCode}) - Project ID: ${w.firebaseProjectId} - GCP Project: ${w.projectNumber}`);
    }
  }

  if (DRY_RUN && (results.unverified.length > 0 || results.missing.length > 0)) {
    console.log('\n💡 Run with --fix to update Firestore documents with verification results.');
  }

  if (!DRY_RUN && SHOULD_FIX) {
    console.log('\n✅ Firestore documents updated with verification results.');
  }

  // Exit with error code if phantoms found
  if (results.missing.length > 0) {
    process.exit(1);
  }
}

main().catch(error => {
  console.error('Fatal error:', error);
  process.exit(1);
});