#!/usr/bin/env node
/**
 * Backfills stale workspace Firebase project IDs in the master Firestore.
 *
 * Repairs workspaces where the top-level `firebaseProjectId` diverged from
 * the nested `firebaseConfig.projectId`. The nested config is treated as the
 * source of truth because it is the uploaded client-side Firebase config used by
 * the onboarding flow.
 *
 * Usage:
 *   node scripts/backfillWorkspaceFirebaseProjectIds.js [--fix] [--dry-run]
 *       [--project <master-project-id>] [--verbose]
 */

const admin = require('firebase-admin');

function parseArgs(argv) {
  const options = {
    fix: false,
    dryRun: false,
    verbose: false,
    project: '',
  };

  for (let i = 2; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];

    if (arg === '--fix') {
      options.fix = true;
      continue;
    }
    if (arg === '--dry-run') {
      options.dryRun = true;
      continue;
    }
    if (arg === '-v' || arg === '--verbose') {
      options.verbose = true;
      continue;
    }
    if (arg === '-p' || arg === '--project') {
      if (!next || next.startsWith('-')) {
        throw new Error('Missing value for --project');
      }
      options.project = next;
      i += 1;
      continue;
    }
    if (arg.startsWith('--project=')) {
      options.project = arg.split('=', 2)[1];
      continue;
    }
    if (arg.startsWith('-p=')) {
      options.project = arg.split('=', 2)[1];
      continue;
    }
  }

  return options;
}

const options = parseArgs(process.argv);
const MASTER_PROJECT_ID = options.project || process.env.GOOGLE_CLOUD_PROJECT || process.env.FIREBASE_PROJECT_ID;
const SHOULD_FIX = options.fix || false;
const DRY_RUN = options.dryRun || false;
const VERBOSE = options.verbose || false;

if (!MASTER_PROJECT_ID) {
  console.error('ERROR: Master project ID not provided. Use --project <id> or set GOOGLE_CLOUD_PROJECT.');
  process.exit(1);
}

function initializeFirebase() {
  if (admin.apps.length > 0) {
    return admin.firestore();
  }

  const saJson = process.env.SERVICE_ACCOUNT_JSON;
  if (saJson) {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(saJson)),
      projectId: MASTER_PROJECT_ID,
    });
  } else {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: MASTER_PROJECT_ID,
    });
  }
  return admin.firestore();
}

function normalizeProjectId(value) {
  return typeof value === 'string' ? value.trim() : '';
}

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║  Workspace Firebase Project ID Backfill                      ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log(`Master Project: ${MASTER_PROJECT_ID}`);
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no changes)' : (SHOULD_FIX ? 'FIX (will update Firestore)' : 'REPORT ONLY')}`);
  console.log('');

  const db = initializeFirebase();
  const snapshot = await db.collection('workspaces').get();
  console.log(`Found ${snapshot.docs.length} workspaces.`);

  const summary = {
    matched: 0,
    repaired: 0,
    skipped: 0,
    missingConfig: 0,
  };

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const workspaceId = doc.id;
    const workspaceCode = data.workspaceCode || 'N/A';
    const companyName = data.companyName || 'Unknown';
    const topLevelProjectId = normalizeProjectId(data.firebaseProjectId);
    const config = data.firebaseConfig && typeof data.firebaseConfig === 'object' ? data.firebaseConfig : {};
    const configProjectId = normalizeProjectId(config.projectId);

    // The nested Firebase config is the source of truth. The top-level
    // firebaseProjectId must always mirror firebaseConfig.projectId so the
    // workspace registry cannot drift into a stale project reference.
    if (!configProjectId) {
      summary.missingConfig += 1;
      if (VERBOSE) {
        console.log(`  ⚠️  ${companyName} (${workspaceCode}) - missing firebaseConfig.projectId, skipping`);
      }
      continue;
    }

    if (topLevelProjectId === configProjectId) {
      summary.matched += 1;
      if (VERBOSE) {
        console.log(`  ✅ ${companyName} (${workspaceCode}) - consistent (${configProjectId})`);
      }
      continue;
    }

    summary.repaired += 1;
    console.log(`  🔧 ${companyName} (${workspaceCode}) - firebaseProjectId="${topLevelProjectId || '(empty)'}" -> "${configProjectId}"`);

    if (SHOULD_FIX && !DRY_RUN) {
      await db.collection('workspaces').doc(workspaceId).update({
        firebaseProjectId: configProjectId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  console.log('');
  console.log('Summary');
  console.log('-------');
  console.log(`Matched:         ${summary.matched}`);
  console.log(`Repaired:        ${summary.repaired}`);
  console.log(`Missing config:   ${summary.missingConfig}`);
  console.log(`Mode:             ${DRY_RUN ? 'dry-run' : (SHOULD_FIX ? 'fix' : 'report-only')}`);
}

main().catch((error) => {
  console.error('Backfill failed:', error);
  process.exit(1);
});
