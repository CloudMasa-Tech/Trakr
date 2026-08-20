const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FUNCTIONS_DIR = '/home/keerthu/keerthana/TRAKR/Trakr/functions';
const DEPLOY_HASH_FILE = path.join(FUNCTIONS_DIR, '.deploy_hash');

function getLatestGitCommitHash() {
  try {
    return execSync('git rev-parse HEAD', { cwd: FUNCTIONS_DIR })
      .toString()
      .trim();
  } catch (e) {
    console.error('Failed to get git commit hash. Are you in a git repo?');
    process.exit(1);
  }
}

function readStoredDeployHash() {
  if (!fs.existsSync(DEPLOY_HASH_FILE)) {
    return null;
  }
  return fs.readFileSync(DEPLOY_HASH_FILE, 'utf8').trim();
}

function storeDeployHash(hash) {
  fs.writeFileSync(DEPLOY_HASH_FILE, hash);
  console.log('Deploy hash stored: ' + hash);
}

try {
  const currentHash = getLatestGitCommitHash();
  const storedHash = readStoredDeployHash();

  if (storedHash && storedHash === currentHash) {
    console.log('Deployment freshness check passed: Source code matches last deployed commit.');
    process.exit(0);
  } else if (storedHash && storedHash !== currentHash) {
    console.error('Deployment freshness check FAILED:');
    console.error('  Current source commit: ' + currentHash);
    console.error('  Last deployed commit:  ' + storedHash);
    console.error('');
    console.error('  The source code has changed since the last deployment, but');
    console.error('  the deployed functions may not have been rebuilt.');
    console.error('');
    console.error('  Please run:  npm run build  (then re-deploy with: npm run deploy)');
    process.exit(1);
  } else {
    console.log('No previous deploy hash found (new repo or first deployment).');
    console.log('  This deploy will proceed, but future deploys will compare against this hash.');
    storeDeployHash(currentHash);
    console.log('  Deploy hash stored: ' + currentHash);
    process.exit(0);
  }
} catch (error) {
  console.error('Deployment freshness check encountered an error: ' + error.message);
  process.exit(1);
}
