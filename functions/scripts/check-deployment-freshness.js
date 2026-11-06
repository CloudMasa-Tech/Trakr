/**
 * Pre-deploy gate: make sure the compiled `lib/` that firebase actually
 * uploads was built from the current `src/`.
 *
 * It deliberately does NOT block on "the git commit moved since the last
 * deploy" — that is the normal state of every deploy (you deploy *because*
 * the source changed). The previous version of this script compared HEAD
 * against `.deploy_hash` and exited 1 on any difference, while only ever
 * writing `.deploy_hash` when the file was missing. Once the two diverged
 * there was no way back: `npm run deploy` aborted every time, and its own
 * advice ("npm run build, then re-deploy") could not clear it. That is how
 * the master project ended up serving a functions build from an older commit
 * than the repo for days.
 *
 * `.deploy_hash` is now written by scripts/record-deploy-hash.js on the
 * POSTdeploy hook, so it records what was actually shipped.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const FUNCTIONS_DIR = path.resolve(__dirname, '..');
const SRC_DIR = path.join(FUNCTIONS_DIR, 'src');
const LIB_DIR = path.join(FUNCTIONS_DIR, 'lib');
const DEPLOY_HASH_FILE = path.join(FUNCTIONS_DIR, '.deploy_hash');

/** Newest mtime under `dir` for files matching `test`, or 0 when none. */
function newestMtime(dir, test) {
  if (!fs.existsSync(dir)) return 0;
  let newest = 0;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      newest = Math.max(newest, newestMtime(full, test));
    } else if (test(entry.name)) {
      newest = Math.max(newest, fs.statSync(full).mtimeMs);
    }
  }
  return newest;
}

function gitHead() {
  try {
    return execSync('git rev-parse HEAD', { cwd: FUNCTIONS_DIR })
      .toString()
      .trim();
  } catch (e) {
    return null;
  }
}

const newestSrc = newestMtime(SRC_DIR, (n) => n.endsWith('.ts'));
const newestLib = newestMtime(LIB_DIR, (n) => n.endsWith('.js'));

if (newestLib === 0) {
  console.error('Pre-deploy check FAILED: functions/lib is empty — nothing compiled to deploy.');
  console.error('  Run:  npm run build');
  process.exit(1);
}

if (newestSrc > newestLib) {
  console.error('Pre-deploy check FAILED: functions/src is newer than the compiled functions/lib.');
  console.error('  Deploying now would ship a stale build.');
  console.error('  Run:  npm run build');
  process.exit(1);
}

console.log('Pre-deploy check passed: functions/lib is built from the current functions/src.');

const head = gitHead();
const stored = fs.existsSync(DEPLOY_HASH_FILE)
  ? fs.readFileSync(DEPLOY_HASH_FILE, 'utf8').trim()
  : null;

if (head && stored && head !== stored) {
  console.log('  Note: last recorded deploy was commit ' + stored.slice(0, 7) + ', deploying ' + head.slice(0, 7) + '.');
} else if (head && !stored) {
  console.log('  Note: no previous deploy recorded; deploying ' + head.slice(0, 7) + '.');
}

process.exit(0);
