#!/usr/bin/env node
/**
 * Provisioning CLI.
 *
 * Phase 1 deliberately builds this BEFORE the HTTP endpoint. The workflow
 * is proven by hand against real Docker until it is boring and reliable,
 * then the exact same `provision()` call is wrapped by
 * POST /control/instances. Automating an unproven procedure just means
 * debugging orchestration and infrastructure at the same time.
 *
 * Usage:
 *   npx tsx src/cli/provision.ts \
 *     --business "James Mini Mart" \
 *     --owner "James Kamau" \
 *     --phone 254712345678 \
 *     --domain retailos.co.ke \
 *     --host ke-host-01 \
 *     --backend-image ghcr.io/acme/shop-api:0.1.0 \
 *     --frontend-image ghcr.io/acme/shop-pos:0.1.0 \
 *     --version 0.1.0 \
 *     --instances-root ./instances \
 *     --dry-run
 *
 * --dry-run performs every step except the ones that touch Docker, so the
 * orchestration and file generation can be inspected safely.
 */
import { buildContext, resolveSlug, slugify } from '../modules/provisioning/context.js';
import {
  createCommandRunner,
  createSecretGenerator,
  hostFs,
  httpPort,
} from '../modules/provisioning/adapters.js';
import { provision, summarise } from '../modules/provisioning/runner.js';
import type { ProvisioningContext, ProvisioningDeps, StepKey } from '../modules/provisioning/types.js';

function arg(name: string, fallback?: string): string | undefined {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const flag = (name: string): boolean => process.argv.includes(`--${name}`);

/** Required flag, or exit with a usage message. */
function required(name: string): string {
  const v = arg(name);
  if (!v) {
    console.error(`Missing required flag: --${name}`);
    process.exit(2);
  }
  return v;
}

async function main(): Promise<number> {
  const businessName = required('business');
  const ownerName = required('owner');
  const ownerPhone = required('phone');
  const baseDomain = arg('domain') ?? 'retailos.local';
  const hostName = arg('host') ?? 'local';
  const version = arg('version') ?? '0.1.0';
  const instancesRoot = arg('instances-root') ?? './instances';
  const dryRun = flag('dry-run');
  const until = arg('until') as StepKey | undefined;

  // Pinned images are mandatory. Default to a clearly-invalid placeholder
  // in dry-run so the user notices they forgot, rather than silently
  // deploying something unintended.
  const images = {
    backend: arg('backend-image') ?? 'MISSING_BACKEND_IMAGE',
    frontend: arg('frontend-image') ?? 'MISSING_FRONTEND_IMAGE',
  };

  const slug = resolveSlug(businessName, [], String(Date.now()));
  const ctx: ProvisioningContext = buildContext({
    businessName,
    ownerName,
    ownerPhone,
    baseDomain,
    backendImage: images.backend,
    frontendImage: images.frontend,
    version,
    host: {
      name: hostName,
      region: arg('region') ?? 'local',
      dockerSocketPath: '/var/run/docker.sock',
    },
    instancesRoot,
    resourceMemoryMb: Number(arg('memory') ?? '1024'),
  });
  ctx.slug = slug;
  ctx.hostname = `${slug}.${baseDomain}`;

  const commands: string[] = [];
  const platformAdminPhone = process.env.POS_SUPER_ADMIN_PHONE;
  const platformAdminPin = process.env.POS_SUPER_ADMIN_PIN;
  if (Boolean(platformAdminPhone) !== Boolean(platformAdminPin)) {
    throw new Error('Set both POS_SUPER_ADMIN_PHONE and POS_SUPER_ADMIN_PIN, or leave both unset.');
  }
  const deps: ProvisioningDeps = {
    runCommand: async (cmd, args, opts) => {
      const safeArgs = args.includes('create-super-admin.js')
        ? [...args.slice(0, -1), '[initial PIN redacted]']
        : args;
      const line = `${cmd} ${safeArgs.join(' ')}`;
      commands.push(line);
      console.log(`    $ ${line}`);
      if (dryRun) return { code: 0, stdout: '(dry-run)', stderr: '' };
      return createCommandRunner()(cmd, args, opts);
    },
    fs: hostFs,
    http: {
      get: async (url, opts) => {
        if (dryRun) return { status: 200, body: { dryRun: true } };
        return httpPort.get(url, opts);
      },
    },
    secrets: createSecretGenerator(),
    platformSuperAdmin: platformAdminPhone && platformAdminPin
      ? { phone: platformAdminPhone, initialPin: platformAdminPin }
      : undefined,
    log: (level, msg, meta) => {
      const line = `[${level}] ${msg}`;
      console.log(`  ${line}${meta ? ` ${JSON.stringify(meta)}` : ''}`);
    },
    sleep: async (ms) => {
      if (!dryRun) await new Promise((r) => setTimeout(r, ms));
    },
  };

  console.log('\nProvisioning');
  console.log(`  Business    ${ctx.businessName}`);
  console.log(`  Slug        ${slugify(ctx.businessName)} -> ${ctx.slug}`);
  console.log(`  Hostname    ${ctx.hostname}`);
  console.log(`  Instance    ${ctx.instanceId} (${ctx.shortId})`);
  console.log(`  Directory   ${ctx.instanceDir}`);
  console.log(`  Version     ${ctx.version}`);
  if (dryRun) console.log('  Mode        DRY RUN (no Docker commands executed)');
  console.log('');

  const started = Date.now();
  const result = await provision(ctx, deps, until ? { until, rollbackOnFailure: false } : {});

  const summary = summarise(result.steps);
  console.log('\nSteps');
  for (const s of result.steps) {
    const mark = s.status === 'SUCCEEDED' ? '✓' : s.status === 'FAILED' ? '✗' : '·';
    console.log(`  ${mark} ${s.displayName}${s.message ? ` — ${s.message}` : ''}`);
    if (s.errorDetail) console.log(`      ${s.errorDetail}`);
  }

  console.log(
    `\n${result.status} — ${summary.completed}/${summary.total} steps ` +
    `(${summary.percent}%) in ${((Date.now() - started) / 1000).toFixed(1)}s`,
  );

  if (result.status === 'SUCCEEDED') {
    console.log(`\nInstance ready: https://${ctx.hostname}`);
    const pin = result.output.pin;
    if (pin) console.log(`Owner PIN (shown once): ${pin}`);
    if (dryRun) console.log(`\nCompose file written to: ${ctx.instanceDir}\\docker-compose.yml`);
  } else {
    console.error(`\nFailed at: ${result.failedStep}`);
    console.error(`Reason: ${result.error}`);
  }

  if (commands.length) {
    console.log(`\nDocker commands issued: ${commands.length}`);
  }

  return result.status === 'SUCCEEDED' ? 0 : 1;
}

main()
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error('Provisioning crashed:', error);
    process.exit(1);
  });
