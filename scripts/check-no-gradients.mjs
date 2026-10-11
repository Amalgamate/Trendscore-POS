#!/usr/bin/env node
import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const ROOT = join(__dirname, '..', 'apps', 'web');
const EXTENSIONS = new Set(['.css', '.tsx', '.ts', '.jsx', '.js']);
const IGNORE_DIRS = new Set(['node_modules', '.next']);
const PATTERN = /gradient\s*\(/i;

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (!IGNORE_DIRS.has(entry.name)) {
        files.push(...await walk(join(dir, entry.name)));
      }
    } else if (EXTENSIONS.has(entry.name.slice(entry.name.lastIndexOf('.')))) {
      files.push(join(dir, entry.name));
    }
  }
  return files;
}

const files = await walk(ROOT);
let found = 0;
for (const file of files) {
  const content = await readFile(file, 'utf8');
  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    if (PATTERN.test(lines[i])) {
      console.log(`${relative(process.cwd(), file)}:${i + 1}  ${lines[i].trim()}`);
      found++;
    }
  }
}
if (found > 0) {
  console.error(`\n✗ ${found} gradient usage(s) found. Remove them.`);
  process.exit(1);
} else {
  console.log('✓ No gradients found.');
}
