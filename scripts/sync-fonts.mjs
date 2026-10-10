/**
 * Copies the bundled UI fonts from npm into the Flutter app.
 *
 * Source: @expo-google-fonts/inter and @expo-google-fonts/jetbrains-mono
 * (static TTFs from Google Fonts, SIL Open Font License 1.1).
 * Target: apps/shop_pos/assets/fonts/  (declared in apps/shop_pos/pubspec.yaml)
 *
 * Run from the repo root after `npm install`:  npm run sync:fonts
 * Commit the copied files; the OFL texts must ship with the fonts.
 */
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const outDir = join(root, 'apps', 'shop_pos', 'assets', 'fonts');
const pkg = (name) => join(root, 'node_modules', '@expo-google-fonts', name);

const INTER = { Regular: '400Regular', Medium: '500Medium', SemiBold: '600SemiBold', Bold: '700Bold' };
const MONO = { Regular: '400Regular', Medium: '500Medium' };

/** [source path, destination file name] */
const jobs = [
  ...Object.entries(INTER).map(([w, dir]) => [
    join(pkg('inter'), dir, `Inter_${dir}.ttf`),
    `Inter-${w}.ttf`,
  ]),
  ...Object.entries(MONO).map(([w, dir]) => [
    join(pkg('jetbrains-mono'), dir, `JetBrainsMono_${dir}.ttf`),
    `JetBrainsMono-${w}.ttf`,
  ]),
  [join(pkg('inter'), 'LICENSE_FONT'), 'OFL-Inter.txt'],
  [join(pkg('jetbrains-mono'), 'LICENSE_FONT'), 'OFL-JetBrainsMono.txt'],
];

const missing = jobs.filter(([src]) => !existsSync(src));
if (missing.length) {
  console.error('[sync-fonts] Missing source files. Run `npm install` at the repo root first:');
  for (const [src] of missing) console.error(`  ${src}`);
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });
for (const [src, name] of jobs) copyFileSync(src, join(outDir, name));
console.log(`[sync-fonts] copied ${jobs.length} files -> ${outDir}`);
