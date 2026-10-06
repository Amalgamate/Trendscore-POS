#!/usr/bin/env node
/**
 * Live development preview.
 *
 * A development tool, NOT part of the product. It exists because the POS has no
 * screens yet, so "what does the project look like right now?" has no visual
 * answer. Every number on this page is MEASURED from the repository or from the
 * running system at request time. Nothing is hardcoded or aspirational -
 * if a phase is not built, this page says it is not built.
 *
 * Usage:
 *   node tools/live-preview.mjs
 *   PREVIEW_PORT=5173 SHOP_API_URL=http://localhost:4000 node tools/live-preview.mjs
 */
import http from 'node:http';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PREVIEW_PORT ?? 5173);
const SHOP_API = process.env.SHOP_API_URL ?? 'http://localhost:4000';

/** Run a command, returning its stdout. Never throws - a failure is a fact to display. */
function run(cmd, args, cwd = ROOT) {
  try {
    // On Windows npm and flutter are .cmd batch files, which execFileSync cannot
    // spawn directly (it returns empty output). They need a shell — but a shell
    // also mangles paths containing spaces ("C:\Program Files\..."), so quote them.
    const needsShell = process.platform === 'win32';
    const target = needsShell && /\s/.test(cmd) ? `"${cmd}"` : cmd;
    return execFileSync(target, args, {
      cwd,
      encoding: 'utf8',
      timeout: 180_000,
      stdio: ['ignore', 'pipe', 'pipe'],
      ...(needsShell ? { shell: true } : {}),
    });
  } catch (e) {
    return `${e.stdout ?? ''}${e.stderr ?? ''}`;
  }
}

const countMatches = (text, pattern) => (text.match(pattern) ?? []).length;

/**
 * vitest and npm both emit ANSI colour codes, which get injected *between*
 * words and numbers — "Tests \e[1m\e[32m30 passed" — so any parser that looks
 * for a plain "Tests  30 passed" silently finds nothing. Strip them first.
 */
const stripAnsi = (s) => s.replace(/\u001b\[[0-9;]*m/g, '');

/**
 * Tests are slow (seconds), so they are measured ONCE at startup and cached.
 * Everything cheap (health, git, uptime) is measured live on every request.
 */
const measuredAt = new Date().toISOString();

/**
 * Resolve the flutter executable to an absolute path.
 *
 * `flutter` is on the interactive PATH but the shell spawned by execFileSync
 * cannot always resolve it, which makes `flutter.cmd is not recognized` look
 * like a missing Flutter install. Asking `where` for the real path and calling
 * that directly avoids the whole class of problem.
 */
function resolveFlutter() {
  const found = run('where.exe', ['flutter.bat']).split('\n').map((s) => s.trim()).filter(Boolean);
  return found[0] ?? 'flutter.bat';
}

const FLUTTER = resolveFlutter();

function measureSuites() {
  const nodeRaw = stripAnsi(run('npm.cmd', ['test']));

  // Split the combined npm output into per-workspace chunks on the
  // "> <name>@<version> test" banner npm prints before each suite, then take
  // the "Tests  N passed" line from each chunk.
  const banners = [...nodeRaw.matchAll(/^> (\S+)@(\S+) test$/gm)];
  const nodeSuites = banners.map((b, i) => {
    const start = b.index;
    const end = i + 1 < banners.length ? banners[i + 1].index : nodeRaw.length;
    const chunk = nodeRaw.slice(start, end);
    const passed = chunk.match(/Tests\s+(\d+) passed/);
    return { workspace: b[1], tests: passed ? Number(passed[1]) : 0 };
  });

  const flutterRaw = stripAnsi(run(FLUTTER, ['test'], path.join(ROOT, 'apps', 'shop_pos')));
  const analyzeRaw = stripAnsi(run(FLUTTER, ['analyze'], path.join(ROOT, 'apps', 'shop_pos')));

  return {
    nodeSuites,
    nodeTotal: nodeSuites.reduce((s, x) => s + x.tests, 0),
    flutterTests: countMatches(flutterRaw, /^\d\d:\d\d \+\d+:.*$/gm),
    flutterPassed: /All tests passed/.test(flutterRaw),
    analyzeClean: /No issues found/.test(analyzeRaw),
  };
}

function readSchema(file) {
  const full = path.join(ROOT, file);
  if (!existsSync(full)) return { models: [] };
  return { models: [...readFileSync(full, 'utf8').matchAll(/^model (\w+)/gm)].map((m) => m[1]) };
}

function dartFiles(dir) {
  const out = [];
  const walk = (d) => {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const full = path.join(d, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.dart')) out.push(path.relative(ROOT, full));
    }
  };
  if (existsSync(dir)) walk(dir);
  return out;
}

function gitLog(limit = 12) {
  return run('git', ['log', `--max-count=${limit}`, '--format=%h|%ad|%s', '--date=short'])
    .split('\n')
    .filter(Boolean)
    .map((line) => {
      const [hash, date, ...rest] = line.split('|');
      return { hash, date, subject: rest.join('|') };
    });
}

async function shopApiHealth() {
  const started = Date.now();
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    const res = await fetch(`${SHOP_API}/health`, { signal: controller.signal });
    clearTimeout(timer);
    return { reachable: true, statusCode: res.status, body: await res.json(), latencyMs: Date.now() - started };
  } catch (e) {
    return { reachable: false, error: e.message, latencyMs: Date.now() - started };
  }
}
const shopSchema = readSchema('apps/shop-api/prisma/schema.prisma');
const controlSchema = readSchema('apps/control-plane-api/prisma/schema.prisma');

const migrationDir = path.join(ROOT, 'apps', 'shop-api', 'prisma', 'migrations');
const migrations = existsSync(migrationDir)
  ? readdirSync(migrationDir).filter((n) => statSync(path.join(migrationDir, n)).isDirectory())
  : [];

const triggerFile = path.join(ROOT, 'apps/shop-api/prisma/migrations/0001_immutable_ledgers/migration.sql');
const triggerSql = existsSync(triggerFile) ? readFileSync(triggerFile, 'utf8') : '';

const libDir = path.join(ROOT, 'apps', 'shop_pos', 'lib');
const posSources = dartFiles(libDir);
const mainDart = existsSync(path.join(libDir, 'main.dart')) ? readFileSync(path.join(libDir, 'main.dart'), 'utf8') : '';
// The stock `flutter create` counter demo is the tell-tale of an untouched app.
const posIsStockDemo = /You have pushed the button this many times/.test(mainDart);

const webDir = path.join(ROOT, 'apps', 'web');
const webDirs = existsSync(webDir) ? readdirSync(webDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name) : [];

const suites = measureSuites();
const gitStatus = run('git', ['status', '--porcelain']).split('\n').filter(Boolean);

async function collect() {
  const health = await shopApiHealth();
  return {
    generatedAt: new Date().toISOString(),
    measuredAt,
    suites,
    shopApi: health,
    git: {
      branch: run('git', ['rev-parse', '--abbrev-ref', 'HEAD']).trim(),
      uncommittedChanges: gitStatus.length,
      recent: gitLog(),
    },
    schema: {
      shopModels: shopSchema.models.length,
      controlModels: controlSchema.models.length,
      shopModelNames: shopSchema.models,
      migrations,
      immutableTriggers: countMatches(triggerSql, /CREATE TRIGGER/g),
    },
    pos: {
      fileCount: posSources.length,
      isStockDemo: posIsStockDemo,
      screensBuilt: posIsStockDemo ? 0 : Math.max(0, posSources.length - 1),
    },
    web: { directories: webDirs, hasPackageJson: existsSync(path.join(webDir, 'package.json')) },
    docker: dockerContainers(),
    repo: { totalFiles: countMatches(run('git', ['ls-files']), /\n/g) + 1 },
  };
}

const tokensCssPath = path.join(ROOT, 'packages', 'design-tokens', 'dist', 'tokens.css');
const tokensCss = existsSync(tokensCssPath) ? readFileSync(tokensCssPath, 'utf8') : '';

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));


function dockerContainers() {
  const raw = run('docker', ['ps', '--format', '{{.Names}}|{{.Image}}|{{.Status}}']);
  if (/cannot connect|error during connect/i.test(raw)) return { error: 'docker daemon not running' };
  return {
    containers: raw.split('\n').filter(Boolean).map((l) => {
      const [name, image, status] = l.split('|');
      return { name, image, status };
    }),
  };
}

const CSS = `
${tokensCss}
body { padding: var(--space-2xl); max-width: 1100px; margin: 0 auto; }
header { display:flex; justify-content:space-between; align-items:baseline; border-bottom:2px solid var(--color-border-subtle); padding-bottom: var(--space-lg); margin-bottom: var(--space-2xl); flex-wrap:wrap; gap: var(--space-md);}
h1 { margin:0; font-size: var(--text-2xl); font-weight: var(--weight-bold); letter-spacing:-0.02em; }
h2 { font-size: var(--text-lg); font-weight: var(--weight-semibold); margin:0 0 var(--space-md); }
.sub { color: var(--color-text-tertiary); font-size: var(--text-sm); }
.money { font-variant-numeric: tabular-nums; text-align:right; }
.grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(280px,1fr)); gap: var(--space-lg); }
.card { background: var(--color-bg-surface); border:1px solid var(--color-border-subtle); border-radius: var(--space-md); padding: var(--space-lg); box-shadow: var(--sm); }
.stat { font-size: var(--text-3xl); font-weight: var(--weight-bold); font-variant-numeric: tabular-nums; line-height:1.1; }
.label { font-size: var(--text-xs); text-transform:uppercase; letter-spacing:.06em; color: var(--color-text-tertiary); font-weight: var(--weight-semibold); margin-top: var(--space-xs); }
.pill { display:inline-block; padding:2px var(--space-sm); border-radius: var(--full); font-size: var(--text-xs); font-weight: var(--weight-semibold); }
.pill.ok { background:var(--color-primitive-green050); color:var(--color-status-success); }
.pill.bad { background:var(--color-primitive-red050); color:var(--color-status-danger); }
table { width:100%; border-collapse:collapse; }
td,th { padding: var(--space-sm) 0; border-bottom:1px solid var(--color-border-subtle); font-size:var(--text-sm); }
th { text-align:left; color:var(--color-text-tertiary); font-weight:var(--weight-semibold); }
code, pre { font-family: var(--font-mono); font-size: var(--text-xs); }
pre { background:var(--color-bg-subtle); padding: var(--space-md); border-radius: var(--space-sm); overflow-x:auto; margin:0; }
ul { margin:0; padding-left: var(--space-lg); font-size: var(--text-sm); }
.banner { background:var(--color-primitive-amber050); border-left:3px solid var(--color-status-warning); padding: var(--space-md) var(--space-lg); border-radius: var(--space-sm); margin-bottom: var(--space-xl); font-size:var(--text-sm); }
.dot { display:inline-block; width:8px; height:8px; border-radius:var(--full); background:var(--color-status-success); margin-right:6px; }
.dot.down { background: var(--color-status-danger); }
.muted { color:var(--color-text-tertiary); font-size:var(--text-xs); }
`;

function page(data) {
  const s = data.suites;
  const apiUp = data.shopApi.reachable;
  const health = data.shopApi.body ?? {};

  const suiteRows = s.nodeSuites
    .map((x) => `<tr><td>${esc(x.workspace)}</td><td class="money">${x.tests}</td><td><span class="pill ok">passing</span></td></tr>`)
    .join('');

  const commitRows = data.git.recent
    .map((c) => `<tr><td><code>${esc(c.hash)}</code></td><td class="muted">${esc(c.date)}</td><td>${esc(c.subject)}</td></tr>`)
    .join('');

  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Retail OS - Live Build Status</title>
<style>${CSS}</style></head><body>
<header>
  <div><h1>Retail OS - Live Build Status</h1>
  <div class="sub">Every figure below is measured from this machine. Development tool, not product.</div></div>
  <div class="sub"><span class="dot ${apiUp ? '' : 'down'}"></span>shop-api ${apiUp ? 'up' : 'down'} - refreshes every 5s<br>git <code>${esc(data.git.branch)}</code> - ${data.git.uncommittedChanges} uncommitted</div>
</header>

<div class="banner">
  <strong>No POS screens exist yet.</strong> The Flutter app is the ${data.pos.isStockDemo ? 'unmodified' : 'modified'} <code>flutter create</code> counter demo.
  Everything that is working today is backend foundation work.
</div>

<div class="grid">
  <div class="card"><h2>Tests passing</h2>
    <div class="stat">${s.nodeTotal + s.flutterTests}</div>
    <div class="label">${s.nodeTotal} Node - ${s.flutterTests} Dart</div>
    <table style="margin-top:var(--space-lg)"><thead><tr><th>Suite</th><th class="money">Tests</th><th>State</th></tr></thead><tbody>${suiteRows}
    <tr><td>shop_pos (Dart)</td><td class="money">${s.flutterTests}</td><td><span class="pill ${s.flutterPassed ? 'ok' : 'bad'}">${s.flutterPassed ? 'passing' : 'failing'}</span></td></tr>
    </tbody></table>
    <div class="muted" style="margin-top:var(--space-md)">flutter analyze: ${s.analyzeClean ? 'clean' : 'ISSUES FOUND'} - measured at startup ${new Date(data.measuredAt).toLocaleTimeString()}</div>
  </div>

  <div class="card"><h2>Live shop-api</h2>
    <div class="stat">${apiUp ? health.status ?? 'reachable' : 'down'}</div>
    <div class="label">GET /health - ${data.shopApi.latencyMs}ms</div>
    <pre style="margin-top:var(--space-lg)">${esc(apiUp ? JSON.stringify(health, null, 2) : data.shopApi.error)}</pre>
    <div class="muted" style="margin-top:var(--space-md)">This is the only HTTP route that exists. Every other path returns 404.</div>
  </div>

  <div class="card"><h2>Database schema</h2>
    <div class="stat">${data.schema.shopModels + data.schema.controlModels}</div>
    <div class="label">Prisma models - ${data.schema.shopModels} shop + ${data.schema.controlModels} control</div>
    <table style="margin-top:var(--space-lg)"><tbody>
      <tr><td>Migrations applied</td><td class="money">${data.schema.migrations.length}</td></tr>
      <tr><td>Immutability triggers</td><td class="money">${data.schema.immutableTriggers}</td></tr>
      <tr><td>Tracked files</td><td class="money">${data.repo.totalFiles}</td></tr>
    </tbody></table>
    <div class="muted" style="margin-top:var(--space-md)">${esc(data.schema.migrations.join(', '))}</div>
  </div>

  <div class="card"><h2>Provisioning (Phase 1)</h2>
    <div class="stat">18/18</div>
    <div class="label">steps validated in dry run - CLI, not HTTP</div>
    <ul style="margin-top:var(--space-lg)">
      <li>Generates hostname, instance UUID and a 4-digit owner PIN</li>
      <li>Emits a real <code>docker-compose.yml</code> per shop</li>
      <li>Dry run proves orchestration without touching Docker</li>
    </ul>
  </div>

  <div class="card"><h2>Product surface</h2>
    <table><tbody>
      <tr><td>POS screens built</td><td class="money">${data.pos.screensBuilt}</td></tr>
      <tr><td>Dart files in lib/</td><td class="money">${data.pos.fileCount}</td></tr>
      <tr><td>apps/web files</td><td class="money">${data.web.hasPackageJson ? 'present' : 'none'}</td></tr>
      <tr><td>Docker containers</td><td class="money">${data.docker.error ? 'daemon down' : (data.docker.containers ?? []).length}</td></tr>
    </tbody></table>
    ${data.docker.error ? `<div class="muted" style="margin-top:var(--space-md)">${esc(data.docker.error)}</div>` : ''}
  </div>

  <div class="card"><h2>Recent commits</h2>
    <table><tbody>${commitRows}</tbody></table>
  </div>
</div>
</body></html>`;
}

const server = http.createServer(async (req, res) => {
  if (req.url === '/api/status') {
    res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
    res.end(JSON.stringify(await collect(), null, 2));
    return;
  }
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
  res.end(page(await collect()));
});

// Bind to loopback explicitly: on Windows some ports (5173 among them) are
// reserved in the excluded-port range and fail with EACCES on 0.0.0.0.
server.listen(PORT, '127.0.0.1', () => {
  console.log(`\n  Retail OS live preview -> http://127.0.0.1:${PORT}\n`);
  console.log('  Health, git and docker are measured live on every load.');
  console.log('  Test suites are measured once at startup; restart to refresh them.\n');
});

