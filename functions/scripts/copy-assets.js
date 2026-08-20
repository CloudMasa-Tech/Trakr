#!/usr/bin/env node
/**
 * Copies firestore.rules and firestore.indexes.json from the repo root
 * into functions/src/assets/ AND functions/lib/assets/.
 *
 * - "prebuild": copies repo-root files into src/assets/ (source of truth)
 * - "postbuild": copies repo-root files into lib/assets/ (deployed bundle)
 *
 * Both hooks run as part of `npm run build`, so a single `npm run build`
 * produces a working bundle with or without a separate CI step.
 */

const fs = require('fs');
const path = require('path');

// Repo root is one level up from functions/
const REPO_ROOT = path.join(__dirname, '..', '..');

// Source assets dir (for IDE / source reference)
const SRC_ASSETS_DIR = path.join(__dirname, '..', 'src', 'assets');
// Compiled assets dir (what actually gets deployed)
const LIB_ASSETS_DIR = path.join(__dirname, '..', 'lib', 'assets');

const FILES = [
  { src: 'firestore.rules', dest: 'firestore.rules' },
  { src: 'firestore.indexes.json', dest: 'firestore.indexes.json' },
];

// Determine target: "prebuild" copies to src/, "postbuild" copies to lib/
const scriptName = process.env.npm_lifecycle_event || '';
const targetDir = scriptName === 'postbuild' ? LIB_ASSETS_DIR : SRC_ASSETS_DIR;
const label = scriptName === 'postbuild' ? 'postbuild' : 'prebuild';

// Ensure target directory exists
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
}

let failed = false;

for (const file of FILES) {
  const srcPath = path.join(REPO_ROOT, file.src);
  const destPath = path.join(targetDir, file.dest);

  if (!fs.existsSync(srcPath)) {
    console.error(`[copy-assets:${label}] ERROR: Source file not found: ${srcPath}`);
    failed = true;
    continue;
  }

  const content = fs.readFileSync(srcPath);
  fs.writeFileSync(destPath, content);

  const size = content.length;
  console.log(`[copy-assets:${label}] Copied ${file.src} (${size} bytes) -> ${path.relative(REPO_ROOT, destPath)}`);
}

if (failed) {
  console.error(`[copy-assets:${label}] One or more source files were missing. Build may be incomplete.`);
  process.exit(1);
}

console.log(`[copy-assets:${label}] All assets copied successfully.`);
