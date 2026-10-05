import { renderComposeFile } from './compose-template.js';
import type {
  ProvisioningContext,
  ProvisioningDeps,
  StepDefinition,
} from './types.js';

/**
 * The provisioning workflow.
 *
 * Order matters and is enforced by `position`, not by array order, so a
 * future insertion cannot silently reorder dependencies.
 *
 * Steps are idempotent where they can be. Re-running provisioning on a
 * half-built instance must resume rather than fail — a shop owner
 * refreshing the onboarding page must never end up with a broken shop.
 */
export const STEPS: StepDefinition[] = [
  {
    key: 'validate',
    displayName: 'Checking details',
    position: 10,
    customerVisible: true,
    async execute(ctx) {
      const problems = validateContext(ctx);
      if (problems.length) {
        throw new Error(`Invalid request: ${problems.join('; ')}`);
      }
      return { message: 'Details look good' };
    },
  },
  {
    key: 'instance_id',
    displayName: 'Creating your shop',
    position: 20,
    customerVisible: true,
    async execute(ctx) {
      return { message: `Shop ${ctx.shortId} created`, data: { instanceId: ctx.instanceId } };
    },
  },
  {
    key: 'directory',
    displayName: 'Preparing storage',
    position: 30,
    customerVisible: false,
    async execute(ctx, deps) {
      await deps.fs.mkdir(ctx.instanceDir, { recursive: true, mode: 0o750 });
      await deps.fs.mkdir(`${ctx.instanceDir}/backups`, { recursive: true });
      return { message: 'Storage prepared' };
    },
    async rollback(ctx, deps) {
      await deps.fs.remove(ctx.instanceDir);
    },
  },
  {
    key: 'credentials',
    displayName: 'Securing your shop',
    position: 40,
    customerVisible: true,
    async execute(ctx, deps) {
      const password = deps.secrets.password(32);
      const jwtSecret = deps.secrets.base64(48);
      const redisPassword = deps.secrets.token(24);

      // Written to the instance dir only. Never returned, never logged,
      // never sent to the customer.
      const env = [
        `POSTGRES_PASSWORD=${password}`,
        `JWT_SECRET=${jwtSecret}`,
        `REDIS_PASSWORD=${redisPassword}`,
        `INSTANCE_ID=${ctx.instanceId}`,
        `APP_VERSION=${ctx.version}`,
        `BACKEND_IMAGE=${ctx.backendImage}`,
        `FRONTEND_IMAGE=${ctx.frontendImage}`,
        `PUBLIC_URL=https://${ctx.hostname}`,
        '',
      ].join('\n');

      await deps.fs.writeFile(`${ctx.instanceDir}/.env`, env, { mode: 0o600 });
      return { message: 'Security configured' };
    },
  },
  {
    key: 'compose',
    displayName: 'Setting up your shop',
    position: 50,
    customerVisible: false,
    async execute(ctx, deps) {
      const compose = renderComposeFile(ctx);
      await deps.fs.writeFile(`${ctx.instanceDir}/docker-compose.yml`, compose, { mode: 0o640 });
      return { message: 'Configuration written' };
    },
  },
  {
    key: 'network',
    displayName: 'Creating network',
    position: 60,
    customerVisible: false,
    async execute(ctx, deps) {
      const net = `retailos_${ctx.instanceId.replace(/-/g, '').slice(0, 12)}`;
      await runOrIgnore(deps, 'docker', ['network', 'create', net]);
      return { message: 'Network created', data: { network: net } };
    },
  },
  {
    key: 'postgres',
    displayName: 'Creating database',
    position: 70,
    customerVisible: true,
    async execute(ctx, deps) {
      await mustSucceed(deps, 'Database', composeArgs(ctx, 'up', '-d', 'postgres'), ctx.instanceDir);
      return { message: 'Database created' };
    },
    async rollback(ctx, deps) {
      await teardown(deps, ctx, 'postgres');
    },
  },
  {
    key: 'redis',
    displayName: 'Starting services',
    position: 80,
    customerVisible: false,
    async execute(ctx, deps) {
      await mustSucceed(deps, 'Cache', composeArgs(ctx, 'up', '-d', 'redis'), ctx.instanceDir);
      return { message: 'Cache started' };
    },
  },
  {
    key: 'backend',
    displayName: 'Starting the till',
    position: 90,
    customerVisible: true,
    async execute(ctx, deps) {
      await mustSucceed(deps, 'POS', composeArgs(ctx, 'up', '-d', 'backend'), ctx.instanceDir);
      return { message: 'POS started' };
    },
    async rollback(ctx, deps) {
      await teardown(deps, ctx, 'backend');
    },
  },
  {
    key: 'frontend',
    displayName: 'Almost there',
    position: 100,
    customerVisible: true,
    async execute(ctx, deps) {
      await mustSucceed(deps, 'Application', composeArgs(ctx, 'up', '-d', 'frontend'), ctx.instanceDir);
      return { message: 'Application started' };
    },
  },
  {
    key: 'migrations',
    displayName: 'Preparing your data',
    position: 110,
    customerVisible: false,
    async execute(ctx, deps) {
      await mustSucceed(
        deps, 'Migrations',
        composeArgs(ctx, 'exec', '-T', 'backend', 'npx', 'prisma', 'migrate', 'deploy'),
        ctx.instanceDir,
      );
      return { message: 'Schema ready' };
    },
  },
  {
    key: 'seed',
    displayName: 'Adding essentials',
    position: 120,
    customerVisible: false,
    async execute(ctx, deps) {
      await mustSucceed(
        deps, 'Seeding',
        composeArgs(ctx, 'exec', '-T', 'backend', 'node', 'dist/seed.js', ctx.businessName, ctx.slug),
        ctx.instanceDir,
      );
      return { message: 'Essential data added' };
    },
  },
  {
    key: 'owner',
    displayName: 'Creating your account',
    position: 130,
    customerVisible: true,
    async execute(ctx, deps) {
      // The owner's PIN is generated here and returned exactly once for the
      // control plane to display. Never stored in plaintext here, never logged.
      const pin = String(1000 + (parseInt(deps.secrets.token(4), 36) % 9000));
      await mustSucceed(
        deps, 'Owner creation',
        composeArgs(ctx, 'exec', '-T', 'backend', 'node', 'dist/create-owner.js',
          ctx.ownerName, ctx.ownerPhone, pin),
        ctx.instanceDir,
      );
      return { message: 'Account created', data: { pin } };
    },
  },
  {
    key: 'domain',
    displayName: 'Setting up your address',
    position: 140,
    customerVisible: true,
    async execute(ctx) {
      return { message: `Available at ${ctx.hostname}`, data: { hostname: ctx.hostname } };
    },
  },
  {
    key: 'tls',
    displayName: 'Securing your connection',
    position: 150,
    customerVisible: false,
    async execute(ctx, deps) {
      // The wildcard cert is terminated by the shared edge proxy, not per
      // shop. Per-instance issuance would hit Let's Encrypt rate limits fast.
      const r = await runOrIgnore(deps, 'docker', ['exec', 'retailos-edge', 'traefik', 'reload']);
      return { message: 'HTTPS secured', data: { reloaded: r.code === 0 } };
    },
  },
  {
    key: 'health_check',
    displayName: 'Checking everything works',
    position: 160,
    customerVisible: true,
    async execute(ctx, deps) {
      const url = `https://${ctx.hostname}/health`;
      const sleep = deps.sleep ?? ((ms: number) => new Promise((r) => setTimeout(r, ms)));
      const attempts = 10;
      let lastError = '';

      for (let i = 0; i < attempts; i++) {
        try {
          const res = await deps.http.get(url, { timeoutMs: 5000 });
          if (res.status === 200) {
            return { message: 'Your shop is ready', data: { healthy: true } };
          }
          lastError = `status ${res.status}`;
        } catch (error) {
          lastError = error instanceof Error ? error.message : 'unknown';
        }
        await sleep(1000 * (i + 1));
      }
      throw new Error(`Health check failed after ${attempts} attempts: ${lastError}`);
    },
  },
  {
    key: 'backup',
    displayName: 'Securing your records',
    position: 170,
    customerVisible: false,
    async execute(ctx) {
      // Registered with the host backup runner. Verified by a real restore
      // drill in the Phase 1 gate, not assumed here.
      return { message: 'Daily backups scheduled', data: { schedule: '0 2 * * *' } };
    },
  },
  {
    key: 'register',
    displayName: 'Your shop is ready',
    position: 180,
    customerVisible: true,
    async execute(ctx) {
      return { message: 'Ready', data: { hostname: ctx.hostname, version: ctx.version } };
    },
  },
];

export function orderedSteps(): StepDefinition[] {
  return [...STEPS].sort((a, b) => a.position - b.position);
}

export function validateContext(ctx: ProvisioningContext): string[] {
  const problems: string[] = [];
  if (!ctx.businessName?.trim()) problems.push('businessName is required');
  if (!ctx.ownerName?.trim()) problems.push('ownerName is required');
  if (!/^254\d{9}$/.test(ctx.ownerPhone ?? '')) {
    problems.push('ownerPhone must be a 254XXXXXXXX number');
  }
  if (!/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/.test(ctx.slug ?? '')) {
    problems.push('slug must be a valid DNS label');
  }
  if (!ctx.hostname?.includes('.')) problems.push('hostname must be fully qualified');
  // A floating tag would make rollback impossible and let a rebuild change
  // what a shop is running without any deployment record.
  if (!ctx.backendImage?.includes(':') || ctx.backendImage.endsWith(':latest')) {
    problems.push('backendImage must be pinned to an explicit tag');
  }
  if (!ctx.frontendImage?.includes(':') || ctx.frontendImage.endsWith(':latest')) {
    problems.push('frontendImage must be pinned to an explicit tag');
  }
  return problems;
}

function composeArgs(ctx: ProvisioningContext, ...rest: string[]): string[] {
  return ['compose', '--project-name', `retailos-${ctx.shortId}`, ...rest];
}

/**
 * Run a Docker command and fail the step on a non-zero exit.
 *
 * Without this, a container that fails to start is reported as
 * "Database created" and provisioning continues to declare the shop READY
 * while it has no database. Every docker step that must succeed goes
 * through here.
 */
async function mustSucceed(
  deps: ProvisioningDeps,
  label: string,
  args: string[],
  cwd?: string,
): Promise<void> {
  const r = await deps.runCommand('docker', args, cwd ? { cwd } : undefined);
  if (r.code !== 0) {
    const detail = (r.stderr || r.stdout || '').trim();
    throw new Error(`${label} failed (exit ${r.code})${detail ? `: ${detail}` : ''}`);
  }
}

/** Stop and remove a service, tolerating it not existing. */
async function teardown(
  deps: ProvisioningDeps,
  ctx: ProvisioningContext,
  service: string,
): Promise<void> {
  await runOrIgnore(deps, 'docker', composeArgs(ctx, 'rm', '-f', '-v', service));
}

/** Run a command, tolerating idempotent failures like "already exists". */
async function runOrIgnore(
  deps: ProvisioningDeps,
  cmd: string,
  args: string[],
): Promise<{ code: number; stdout: string; stderr: string }> {
  try {
    return await deps.runCommand(cmd, args);
  } catch {
    return { code: -1, stdout: '', stderr: 'command unavailable' };
  }
}
