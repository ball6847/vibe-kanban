// Goal aid: find web-core files orphaned by deletions made during the remote-removal loop.
//
// A file is "broken" when it imports an internal path whose basename matches a file that THIS
// loop actually deleted (git diff vs BASE) and the path no longer resolves. Prevents both
// false positives (unrelated .d.ts / directory imports) and over-deletion of core files.
//
// Usage: node scripts/find-remote-only-web-core.mjs
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';

const BASE = process.env.GOAL_BASE_SHA || '4deb7eca';
const WC = 'packages/web-core/src';
const EXT_ROOTS = ['packages/local-web/src', 'packages/ui/src'];
const importRe = /from ['"]([^'"]+)['"]/g;

const deletedFiles = execSync(`git diff --name-only --diff-filter=D ${BASE}..HEAD`)
  .toString()
  .trim()
  .split('\n')
  .filter(Boolean);
const deletedBase = new Set(
  deletedFiles.map((p) => path.basename(p).replace(/\.(d\.ts|tsx|ts)$/, ''))
);

const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.tsx?$/.test(e.name)) files.push(p);
  }
})(WC);

const ext = [];
for (const root of EXT_ROOTS) {
  if (!fs.existsSync(root)) continue;
  (function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.tsx?$/.test(e.name)) ext.push(p);
    }
  })(root);
}

const src = new Map(files.map((f) => [f, fs.readFileSync(f, 'utf8')]));

function candidates(from, spec) {
  let base;
  if (spec.startsWith('@/')) base = path.join(WC, spec.slice(2));
  else if (spec.startsWith('@web/')) base = path.join(WC, spec.slice(5));
  else if (spec.startsWith('.')) base = path.resolve(path.dirname(from), spec);
  else return null;
  return [base, base + '.ts', base + '.tsx', base + '.d.ts',
          path.join(base, 'index.ts'), path.join(base, 'index.tsx')];
}
function resolve(from, spec) {
  const c = candidates(from, spec);
  if (!c) return null;
  for (const f of c) if (fs.existsSync(f) && fs.statSync(f).isFile()) return f;
  for (const f of c) if (fs.existsSync(f)) return f;
  return null;
}
function referencesDeleted(from, spec) {
  if (!spec.startsWith('@/') && !spec.startsWith('.') && !spec.startsWith('@web/')) return false;
  const seg = spec.replace(/\/(index)?$/, '').split('/').pop();
  if (!deletedBase.has(seg)) return false;
  return resolve(from, spec) === null;
}

const broken = new Set(files.filter((f) =>
  [...src.get(f).matchAll(importRe)].some((m) => referencesDeleted(f, m[1]))));

const importedBy = new Map(files.map((f) => [f, new Set()]));
for (const f of files) {
  for (const m of src.get(f).matchAll(importRe)) {
    const r = resolve(f, m[1]);
    if (r && importedBy.has(r)) importedBy.get(r).add(f);
  }
}
for (const f of ext) {
  const s = fs.readFileSync(f, 'utf8');
  for (const m of s.matchAll(importRe)) {
    const r = resolve(f, m[1]);
    if (r && importedBy.has(r)) importedBy.get(r).add('EXT:' + f);
  }
}

const doomed = new Set(broken);
let changed = true;
while (changed) {
  changed = false;
  for (const f of [...doomed]) {
    if ([...importedBy.get(f)].filter((i) => !doomed.has(i)).length > 0) {
      doomed.delete(f);
      changed = true;
    }
  }
}

console.log(`deletedSinceBase=${deletedFiles.length} total=${files.length} broken=${broken.size} doomed=${doomed.size}`);
console.log([...doomed].sort().join('\n'));
