#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const PLAN_PATH = join(__dirname, '..', 'STOREFRONT_PLAN.md');

const content = await readFile(PLAN_PATH, 'utf8');
const lines = content.split('\n');

// Parse checkboxes per phase
const phases = {}; // phase number -> { done, pending, skipped }
let currentPhase = null;

for (const line of lines) {
  const phaseMatch = line.match(/^## Phase (\d+):/);
  if (phaseMatch) {
    currentPhase = parseInt(phaseMatch[1], 10);
    if (!phases[currentPhase]) phases[currentPhase] = { done: 0, pending: 0, skipped: 0 };
    continue;
  }
  if (currentPhase === null) continue;
  // Stop counting when we hit another h2 that isn't a phase
  if (line.match(/^## (?!Phase)/) ) {
    currentPhase = null;
    continue;
  }
  if (line.includes('- [x]')) phases[currentPhase].done++;
  else if (line.includes('- [ ]')) phases[currentPhase].pending++;
  else if (line.includes('- [~]')) phases[currentPhase].skipped++;
}

// Print per-phase table
console.log('\nPhase progress (from checkboxes):');
console.log('Phase | Done | Pending | Skipped | Total');
console.log('------|------|---------|---------|------');
let sumDone = 0, sumTotal = 0;
for (const [phase, counts] of Object.entries(phases).sort((a,b) => a[0]-b[0])) {
  const total = counts.done + counts.pending + counts.skipped;
  console.log(`  ${phase}   |  ${counts.done}  |    ${counts.pending}    |    ${counts.skipped}    |   ${total}`);
  sumDone += counts.done;
  sumTotal += total;
}
console.log(`Total: ${sumDone} / ${sumTotal}`);

// Parse dashboard table
const dashboardStart = content.indexOf('## Progress dashboard');
if (dashboardStart === -1) {
  console.error('ERROR: Progress dashboard section not found in STOREFRONT_PLAN.md');
  process.exit(1);
}
const dashboardSection = content.slice(dashboardStart);
const tableRows = dashboardSection.split('\n').filter(l => l.startsWith('|'));

let errors = 0;
for (const row of tableRows) {
  const cells = row.split('|').map(c => c.trim()).filter(Boolean);
  if (cells.length < 4) continue;
  // Skip header row
  if (cells[0] === 'Phase' || cells[0] === '---' || cells[0].startsWith('-')) continue;
  
  const phaseCell = cells[0];
  const doneTotal = cells[3]; // "Done / Total" column
  
  // Parse "X / Y" or "0 / 14"
  const dtMatch = doneTotal.match(/(\d+)\s*\/\s*(\d+)/);
  if (!dtMatch) continue;
  
  const declaredDone = parseInt(dtMatch[1], 10);
  const declaredTotal = parseInt(dtMatch[2], 10);
  
  // Handle Total row
  if (phaseCell.toLowerCase().includes('total') || phaseCell === '') {
    if (declaredDone !== sumDone || declaredTotal !== sumTotal) {
      console.error(`ERROR: Dashboard Total row says "${declaredDone} / ${declaredTotal}" but actual is "${sumDone} / ${sumTotal}"`);
      errors++;
    }
    continue;
  }
  
  const phaseNum = parseInt(phaseCell, 10);
  if (isNaN(phaseNum)) continue;
  
  const actual = phases[phaseNum];
  if (!actual) {
    console.error(`ERROR: Dashboard references Phase ${phaseNum} but no such phase found in checkboxes`);
    errors++;
    continue;
  }
  
  const actualTotal = actual.done + actual.pending + actual.skipped;
  if (declaredDone !== actual.done || declaredTotal !== actualTotal) {
    console.error(`ERROR: Phase ${phaseNum} dashboard says "${declaredDone} / ${declaredTotal}" but actual is "${actual.done} / ${actualTotal}"`);
    errors++;
  }
}

if (errors === 0) {
  console.log('\n✓ Dashboard matches checkboxes.');
  process.exit(0);
} else {
  console.error(`\n✗ ${errors} dashboard mismatch(es) found.`);
  process.exit(1);
}
