#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <tenant-project-id> [...]" >&2
  exit 64
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for tenant_project_id in "$@"; do
  firebase deploy \
    --only firestore:rules \
    --project "$tenant_project_id" \
    --config "$REPO_DIR/firebase.tenant.json"
done
