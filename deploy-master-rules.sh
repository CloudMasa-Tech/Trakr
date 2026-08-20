#!/bin/bash
set -e

###############################################################################
# deploy-master-rules.sh
# Safely swaps in master Firestore rules, deploys to the control-plane project,
# and restores the tenant rules file — eliminating the risk of deploying the
# wrong ruleset to the wrong project.
#
# firebase.json always points to `firestore.rules` (the tenant rules file).
# Running `firebase deploy --only firestore:rules --project trakradminsetup-28437`
# directly would push the TENANT rules to MASTER. This script prevents that.
###############################################################################

# ────────────────────────────────────────────────────────────────────────────
# Safety check: master rules file must exist
# ────────────────────────────────────────────────────────────────────────────
if [ ! -f firestore.rules.master ]; then
  echo "❌ ERROR: firestore.rules.master not found in repo root."
  echo "       This file is the master/control-plane Firestore ruleset."
  echo "       Create it (see firestore.rules.master in the repo) before running this script."
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Safety check: prevent overwriting a leftover backup from a failed prior run
# ────────────────────────────────────────────────────────────────────────────
if [ -f firestore.rules.tenant-backup ]; then
  echo "❌ ERROR: firestore.rules.tenant-backup already exists."
  echo "       A previous run of this script likely failed or was interrupted"
  echo "       mid-way and never cleaned up the backup. Please manually inspect"
  echo "       and remove firestore.rules.tenant-backup, then re-run."
  exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Step 1: Backup the current tenant rules file
# ────────────────────────────────────────────────────────────────────────────
echo "📦 Backing up tenant firestore.rules..."
cp firestore.rules firestore.rules.tenant-backup

# ────────────────────────────────────────────────────────────────────────────
# Step 2: Swap in the master rules file
# ────────────────────────────────────────────────────────────────────────────
echo "🔄 Swapping in master rules..."
cp firestore.rules.master firestore.rules

# ────────────────────────────────────────────────────────────────────────────
# Step 3: Deploy to the master project only
# ────────────────────────────────────────────────────────────────────────────
echo "🚀 Deploying to master project (trakradminsetup-28437)..."
firebase deploy --only firestore:rules --project trakradminsetup-28437

# ────────────────────────────────────────────────────────────────────────────
# Step 4: Restore the tenant rules file
# ────────────────────────────────────────────────────────────────────────────
echo "♻️  Restoring tenant firestore.rules..."
cp firestore.rules.tenant-backup firestore.rules
rm firestore.rules.tenant-backup

# ────────────────────────────────────────────────────────────────────────────
# Success output
# ────────────────────────────────────────────────────────────────────────────
echo "✅ Master rules deployed. firestore.rules restored to tenant version."
echo ""
echo "📌 Verify master rules at:"
echo "   https://console.firebase.google.com/project/trakradminsetup-28437/firestore/rules"
echo ""
echo "📌 Tenant rules UI (for reference):"
echo "   firebase deploy --only firestore:rules --project <tenant-project-id>"
echo "   (safe as-is — firebase.json points to firestore.rules which is the tenant rules file)"