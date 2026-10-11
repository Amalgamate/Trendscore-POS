import { copyFile, mkdir, readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import sharp from 'sharp';

const root = process.cwd();
const sourcePath = resolve(root, 'packages/brand-assets/shopsmart-leaf.svg');
const svg = await readFile(sourcePath);

async function writePng(path, size) {
  const output = resolve(root, path);
  await mkdir(dirname(output), { recursive: true });
  await sharp(svg).resize(size, size).png().toFile(output);
}

async function writeSvg(path) {
  const output = resolve(root, path);
  await mkdir(dirname(output), { recursive: true });
  await copyFile(sourcePath, output);
}

await Promise.all([
  writeSvg('apps/web/app/icon.svg'),
  writeSvg('apps/shop_pos/web/shopsmart-leaf.svg'),
  writePng('apps/web/app/apple-icon.png', 180),
  writePng('apps/shop_pos/web/favicon.png', 64),
  writePng('apps/shop_pos/web/icons/Icon-192.png', 192),
  writePng('apps/shop_pos/web/icons/Icon-512.png', 512),
  writePng('apps/shop_pos/web/icons/Icon-maskable-192.png', 192),
  writePng('apps/shop_pos/web/icons/Icon-maskable-512.png', 512),
]);

console.log('Synchronized ShopSmart leaf icons for the website and POS.');
