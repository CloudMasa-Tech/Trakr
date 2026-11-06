/**
 * Post-deploy hook: record the commit that was actually shipped, so
 * `.deploy_hash` reflects production instead of whatever commit happened to
 * be checked out the first time the pre-deploy check ran.
 *
 * Never fails the deploy — by the time this runs the functions are already
 * live, so a bookkeeping error must not be reported as a deploy failure.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FUNCTIONS_DIR = path.resolve(__dirname, '..');
const DEPLOY_HASH_FILE = path.join(FUNCTIONS_DIR, '.deploy_hash');

try {
  const head = execSync('git rev-parse HEAD', { cwd: FUNCTIONS_DIR })
    .toString()
    .trim();
  fs.writeFileSync(DEPLOY_HASH_FILE, head + '\n');
  console.log('Recorded deployed commit: ' + head);
} catch (e) {
  console.warn('Could not record the deployed commit (deploy itself succeeded): ' + e.message);
}
