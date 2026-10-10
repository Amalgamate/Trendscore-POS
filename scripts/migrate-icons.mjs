/**
 * Rewrites Material icon usages in apps/shop_pos/lib to the AppIcons layer:
 *     Icons.inventory_2_outlined  ->  AppIcons.inventory
 * and adds the relative import of shared/icons.dart where needed.
 *
 *   node scripts/migrate-icons.mjs          dry run: prints what would change
 *   node scripts/migrate-icons.mjs --write  apply the changes
 *
 * Run `node scripts/gen-icons.mjs` first so lib/shared/icons.dart exists.
 * Review the result with `git diff` and `dart analyze lib`.
 */
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, posix, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MATERIAL_TO_SEMANTIC } from './icon-map.mjs';

const WRITE = process.argv.includes('--write');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const libDir = join(root, 'apps', 'shop_pos', 'lib');
const iconsFile = join(libDir, 'shared', 'icons.dart');

if (!existsSync(iconsFile)) {
  console.error('[migrate-icons] lib/shared/icons.dart not found. Run `node scripts/gen-icons.mjs` first.');
  process.exit(1);
}

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith('.dart') ? [p] : [];
  });
}

// \b before "Icons" excludes CupertinoIcons and AppIcons.
const RE = /\bIcons\.([A-Za-z0-9_]+)/g;
const unmapped = new Map();
let filesChanged = 0;
let replacements = 0;

for (const file of walk(libDir)) {
  if (file === iconsFile) continue;
  const src = readFileSync(file, 'utf8');
  let count = 0;

  const out = src.replace(RE, (whole, name) => {
    const sem = MATERIAL_TO_SEMANTIC.get(name);
    if (!sem) {
      unmapped.set(`Icons.${name}`, (unmapped.get(`Icons.${name}`) ?? 0) + 1);
      return whole;
    }
    count++;
    return `AppIcons.${sem}`;
  });
  if (count === 0) continue;

  // Add the import (relative, matching the project's existing style).
  const eol = src.includes('\r\n') ? '\r\n' : '\n';
  let next = out;
  const rel = posix.normalize(relative(dirname(file), iconsFile).replaceAll('\\', '/'));
  const importLine = `import '${rel}';`;
  if (!next.includes(importLine)) {
    const lines = next.split(/\r?\n/);
    let last = -1;
    lines.forEach((l, i) => { if (/^import\s/.test(l)) last = i; });
    lines.splice(last + 1, 0, importLine);
    next = lines.join(eol);
  }

  filesChanged++;
  replacements += count;
  console.log(`${String(count).padStart(4)}  ${relative(libDir, file).replaceAll('\\', '/')}`);
  if (WRITE) writeFileSync(file, next);
}

console.log(`\n${replacements} replacements in ${filesChanged} files ${WRITE ? '(written)' : '(DRY RUN: nothing written; re-run with --write)'}`);
if (unmapped.size) {
  console.log('\nNot in icon-map.mjs (left untouched):');
  for (const [n, c] of unmapped) console.log(`  ${n} x${c}`);
}
