/**
 * UI audit: counts hard-coded styling in apps/shop_pos/lib.
 *
 * Usage (from the repo root):
 *   node scripts/ui-audit.mjs            # writes docs/ui-uplift/audit.md
 *   node scripts/ui-audit.mjs --check    # exits 1 if any violation remains
 *
 * Scanned: every .dart file under apps/shop_pos/lib, EXCEPT lib/theme/
 * and lib/shared/widgets/ (those are where raw values are allowed to live).
 */
import { readdirSync, readFileSync, writeFileSync, mkdirSync, statSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const libDir = join(root, 'apps', 'shop_pos', 'lib');
const outFile = join(root, 'docs', 'ui-uplift', 'audit.md');
const checkMode = process.argv.includes('--check');

const ALLOWED_DIRS = [join(libDir, 'theme'), join(libDir, 'shared', 'widgets')];

/** name -> regex. Each match counts as one violation. */
const RULES = {
  'Colors.*': /\bColors\.[A-Za-z_]+/g,
  'Color(0x…)': /\bColor\(\s*0x[0-9A-Fa-f]+\s*\)/g,
  'BorderRadius.circular': /\bBorderRadius\.circular\(/g,
  'Radius.circular': /\bRadius\.circular\(/g,
  'fontSize:': /\bfontSize\s*:/g,
  'EdgeInsets.*': /\bEdgeInsets\.[A-Za-z]+\(/g,
  'Icons.*': /\bIcons\.[A-Za-z_0-9]+/g,
  'CupertinoIcons.*': /\bCupertinoIcons\.[A-Za-z_0-9]+/g,
  'SnackBar': /\bSnackBar\b/g,
  'BoxShadow': /\bBoxShadow\(/g,
  'Gradient': /\b(Linear|Radial|Sweep)Gradient\(/g,
};
const RULE_NAMES = Object.keys(RULES);

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) out.push(...walk(p));
    else if (name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const files = walk(libDir).filter(
  (f) => !ALLOWED_DIRS.some((d) => f === d || f.startsWith(d + sep)),
);

const rows = files.map((f) => {
  const src = readFileSync(f, 'utf8');
  const counts = {};
  let total = 0;
  for (const [name, re] of Object.entries(RULES)) {
    const n = (src.match(re) || []).length;
    counts[name] = n;
    total += n;
  }
  return {
    file: relative(libDir, f).split(sep).join('/'),
    lines: src.split('\n').length,
    counts,
    total,
  };
});

rows.sort((a, b) => b.total - a.total);

const totals = Object.fromEntries(RULE_NAMES.map((n) => [n, rows.reduce((s, r) => s + r.counts[n], 0)]));
const grand = rows.reduce((s, r) => s + r.total, 0);

const header = ['File', 'Lines', ...RULE_NAMES, 'Total'];
const md = [];
md.push('# UI audit: hard-coded styling');
md.push('');
md.push(`Generated: ${new Date().toISOString()}`);
md.push('');
md.push('Scope: `apps/shop_pos/lib/**/*.dart` excluding `theme/` and `shared/widgets/`.');
md.push('Goal: **0** in every column by the end of Phase 7. Re-run with `node scripts/ui-audit.mjs`.');
md.push('');
md.push(`**Grand total: ${grand}**`);
md.push('');
md.push('| ' + header.join(' | ') + ' |');
md.push('|' + header.map((_, i) => (i === 0 ? '---' : '---:')).join('|') + '|');
for (const r of rows) {
  md.push(`| \`${r.file}\` | ${r.lines} | ${RULE_NAMES.map((n) => r.counts[n]).join(' | ')} | **${r.total}** |`);
}
md.push(`| **TOTAL** | | ${RULE_NAMES.map((n) => `**${totals[n]}**`).join(' | ')} | **${grand}** |`);
md.push('');

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, md.join('\n'));

console.log(`Scanned ${rows.length} files. Grand total violations: ${grand}`);
for (const n of RULE_NAMES) console.log(`  ${n.padEnd(24)} ${totals[n]}`);
console.log(`Top files:`);
for (const r of rows.slice(0, 5)) console.log(`  ${String(r.total).padStart(5)}  ${r.file}`);
console.log(`Wrote ${relative(root, outFile)}`);

if (checkMode && grand > 0) process.exit(1);
