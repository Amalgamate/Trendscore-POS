/**
 * Lists every Material / Cupertino icon used in apps/shop_pos/lib.
 * Input for building the Lucide mapping in lib/shared/icons.dart.
 *
 *   node scripts/icon-report.mjs
 *
 * Prints "name  count  files" sorted by count, and writes
 * docs/ui-uplift/icons-used.json.
 */
import { readdirSync, readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const libDir = join(root, 'apps', 'shop_pos', 'lib');

function walk(dir) {
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith('.dart') ? [p] : [];
  });
}

const RE = /\b(Icons|CupertinoIcons)\.([A-Za-z0-9_]+)/g;
const used = new Map(); // "Icons.name" -> { count, files:Set }
let total = 0;

for (const file of walk(libDir)) {
  const rel = relative(libDir, file).replaceAll('\\', '/');
  for (const m of readFileSync(file, 'utf8').matchAll(RE)) {
    const key = `${m[1]}.${m[2]}`;
    const e = used.get(key) ?? { count: 0, files: new Set() };
    e.count++;
    e.files.add(rel);
    used.set(key, e);
    total++;
  }
}

const rows = [...used.entries()]
  .map(([name, e]) => ({ name, count: e.count, files: [...e.files].sort() }))
  .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));

for (const r of rows) console.log(`${r.name.padEnd(46)} ${String(r.count).padStart(4)}  ${r.files.length} file(s)`);
console.log(`\n${rows.length} distinct icons, ${total} usages`);

const outDir = join(root, 'docs', 'ui-uplift');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'icons-used.json'), JSON.stringify({ total, distinct: rows.length, icons: rows }, null, 2));
console.log(`wrote ${join(outDir, 'icons-used.json')}`);
