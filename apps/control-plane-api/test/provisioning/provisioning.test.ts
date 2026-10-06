import { describe, expect, it } from 'vitest';
import { parse as parseYaml } from 'yaml';
import { provision, summarise, customerVisibleSteps } from '../../src/modules/provisioning/runner.js';
import { orderedSteps, validateContext, STEPS } from '../../src/modules/provisioning/steps.js';
import { renderComposeFile } from '../../src/modules/provisioning/compose-template.js';
import { makeContext, makeDeps, succeeded } from './helpers.js';

/**
 * The generated compose file is parsed as YAML here, not just string-matched.
 *
 * A substring assertion passed while the file was syntactically invalid —
 * nested unescaped quotes in the redis healthcheck produced YAML that
 * Docker refused to load. Every shop would have failed to provision and
 * the unit tests were green. Parsing catches that class of bug.
 */
describe('compose template is valid YAML', () => {
  const parsed = () => parseYaml(renderComposeFile(makeContext())) as {
    services: Record<string, { ports?: unknown; healthcheck?: { test?: string[] } }>;
  };

  it('parses as YAML', () => {
    expect(() => parseYaml(renderComposeFile(makeContext()))).not.toThrow();
  });

  it('parses for every supported memory size', () => {
    for (const mb of [512, 1024, 2048, 4096]) {
      expect(() => parseYaml(renderComposeFile(makeContext({ resourceMemoryMb: mb })))).not.toThrow();
    }
  });

  it('parses when the business name contains YAML metacharacters', () => {
    // A shop called 'James: Mini Mart' or 'A "B" Ltd' must not break the file.
    for (const name of ['James: Mini Mart', 'A "B" Ltd', 'Shop #1', 'Yabaa {Ltd}', '- dash']) {
      expect(() => parseYaml(renderComposeFile(makeContext({ businessName: name })))).not.toThrow();
    }
  });

  it('still publishes no ports once parsed', () => {
    const doc = parsed();
    for (const [svc, cfg] of Object.entries(doc.services)) {
      expect(cfg.ports, `${svc} must not publish ports`).toBeUndefined();
    }
  });

  it('keeps the redis healthcheck as a single well-formed command', () => {
    const test = parsed().services.redis?.healthcheck?.test;
    expect(test).toHaveLength(2);
    expect(test?.[0]).toBe('CMD-SHELL');
    // $$ is Docker's escape for a literal $ in compose files.
    expect(test?.[1]).toContain('$$REDIS_PASSWORD');
    expect(test?.[1]).toContain('ping');
  });
});
describe('workflow definition', () => {
  it('has unique step keys', () => {
    const keys = STEPS.map((s) => s.key);
    expect(new Set(keys).size).toBe(keys.length);
  });

  it('has unique positions so ordering is unambiguous', () => {
    const positions = STEPS.map((s) => s.position);
    expect(new Set(positions).size).toBe(positions.length);
  });

  it('sorts by position rather than declaration order', () => {
    const positions = orderedSteps().map((s) => s.position);
    expect([...positions].sort((a, b) => a - b)).toEqual(positions);
  });

  it('puts health_check after the containers it probes', () => {
    const steps = orderedSteps();
    expect(steps.findIndex((s) => s.key === 'health_check')).toBeGreaterThan(
      steps.findIndex((s) => s.key === 'backend'),
    );
    expect(steps.findIndex((s) => s.key === 'migrations')).toBeGreaterThan(
      steps.findIndex((s) => s.key === 'backend'),
    );
  });

  it('runs migrations after the database exists', () => {
    const steps = orderedSteps();
    expect(steps.findIndex((s) => s.key === 'migrations')).toBeGreaterThan(
      steps.findIndex((s) => s.key === 'postgres'),
    );
  });
});

describe('validateContext', () => {
  it('accepts a well-formed request', () => {
    expect(validateContext(makeContext())).toEqual([]);
  });

  it('rejects unpinned images', () => {
    // A floating tag makes rollback impossible and lets a rebuild silently
    // change what a shop is running.
    expect(validateContext(makeContext({ backendImage: 'shop-api:latest' }))).toContain(
      'backendImage must be pinned to an explicit tag',
    );
    expect(validateContext(makeContext({ frontendImage: 'shop-pos' }))).toContain(
      'frontendImage must be pinned to an explicit tag',
    );
  });

  it('rejects a non-Kenyan phone number', () => {
    expect(validateContext(makeContext({ ownerPhone: '0712345678' }))).toContain(
      'ownerPhone must be a 254XXXXXXXX number',
    );
    expect(validateContext(makeContext({ ownerPhone: '25471234567' })).length).toBeGreaterThan(0);
  });

  it('rejects an empty business name', () => {
    expect(validateContext(makeContext({ businessName: '   ' }))).toContain(
      'businessName is required',
    );
  });

  it('rejects a bare hostname', () => {
    expect(validateContext(makeContext({ hostname: 'localhost' }))).toContain(
      'hostname must be fully qualified',
    );
  });
});

describe('compose template', () => {
  const yaml = renderComposeFile(makeContext());

  it('publishes no host ports', () => {
    // The single most important property. Publishing 5432 would put every
    // shop's database on the open internet.
    expect(yaml).not.toMatch(/^\s*ports:/m);
    expect(yaml).not.toContain('5432:');
    expect(yaml).not.toContain('6379:');
    expect(yaml).not.toContain('4000:');
  });

  it('inlines no secrets', () => {
    expect(yaml).toContain('${POSTGRES_PASSWORD}');
    expect(yaml).not.toMatch(/POSTGRES_PASSWORD=\S/);
  });

  it('requires redis auth and healthy dependencies before starting', () => {
    expect(yaml).toContain('condition: service_healthy');
    expect(yaml).toContain('--requirepass');
  });

  it('caps memory so one shop cannot starve its neighbours', () => {
    expect(yaml).toContain('memory: 1024M');
    expect(renderComposeFile(makeContext({ resourceMemoryMb: 2048 }))).toContain('memory: 2048M');
  });

  it('tags the instance so the control plane can inventory it', () => {
    expect(yaml).toContain('retailos.instance=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  });
});

describe('provision runner', () => {
  it('runs every step to success', async () => {
    const r = makeDeps();
    const result = await provision(makeContext(), r.deps);

    expect(result.status).toBe('SUCCEEDED');
    expect(result.steps.every((s) => s.status === 'SUCCEEDED')).toBe(true);
    expect(result.output.hostname).toBe('james-mini-mart.retailos.local');
  });

  it('stops at the first failure and reports which step', async () => {
    const r = makeDeps();
    r.failOn('up -d postgres', 'port already allocated');

    const result = await provision(makeContext(), r.deps);

    expect(result.status).toBe('FAILED');
    expect(result.failedStep).toBe('postgres');
    expect(result.error).toContain('port already allocated');
    // Nothing after the failure should have run.
    expect(r.commands.some((c) => c.includes('up -d backend'))).toBe(false);
  });

  it('retries the health check before giving up', async () => {
    const r = makeDeps();
    r.httpStatuses.push(503, 503, 200);

    const result = await provision(makeContext(), r.deps);

    expect(result.status).toBe('SUCCEEDED');
    expect(result.output.healthy).toBe(true);
  });

  it('fails provisioning when the shop never becomes healthy', async () => {
    const r = makeDeps();
    for (let i = 0; i < 12; i++) r.httpStatuses.push(503);

    const result = await provision(makeContext(), r.deps);

    expect(result.status).toBe('FAILED');
    expect(result.failedStep).toBe('health_check');
    expect(result.error).toContain('Health check failed');
  });

  it('resumes from completed steps instead of rebuilding', async () => {
    const r = makeDeps();
    const result = await provision(makeContext(), r.deps, {
      resumeFrom: succeeded([], ['validate', 'instance_id', 'directory', 'credentials', 'compose']),
    });

    expect(result.status).toBe('SUCCEEDED');
    // Filesystem steps were skipped, so nothing was rewritten.
    expect(r.fs.dirs).toHaveLength(0);
  });

  it('emits step transitions for progress streaming', async () => {
    const r = makeDeps();
    await provision(makeContext(), r.deps);

    const running = r.events.filter((e) => e.status === 'RUNNING').map((e) => e.key);
    const succeededEvents = r.events.filter((e) => e.status === 'SUCCEEDED').map((e) => e.key);
    expect(running[0]).toBe('validate');
    expect(succeededEvents).toContain('register');
    expect(r.events.length).toBe(running.length * 2);
  });

  it('rolls back completed steps on failure', async () => {
    const r = makeDeps();
    r.failOn('up -d postgres');

    await provision(makeContext(), r.deps);

    expect(r.fs.removed).toContain('/tmp/instances/aaaaaa');
  });

  it('can skip rollback so an operator can inspect state', async () => {
    const r = makeDeps();
    r.failOn('up -d postgres');

    await provision(makeContext(), r.deps, { rollbackOnFailure: false });

    expect(r.fs.removed).toHaveLength(0);
  });

  it('never writes secrets into the log stream', async () => {
    const lines: string[] = [];
    const r = makeDeps({
      log: (level, msg, meta) => lines.push(`${level} ${msg} ${JSON.stringify(meta ?? {})}`),
    });

    await provision(makeContext(), r.deps);

    const joined = lines.join('\n');
    expect(joined).not.toContain('POSTGRES_PASSWORD');
    expect(joined).not.toContain('pppppp');
    expect(joined).not.toContain('JWT_SECRET');
  });

  it('writes credentials to a dedicated file, not into the compose file', async () => {
    const r = makeDeps();
    await provision(makeContext(), r.deps, { until: 'credentials' });

    const env = r.fs.files.get('/tmp/instances/aaaaaa/.env');
    expect(env).toContain('POSTGRES_PASSWORD=');
    expect(env).toContain('JWT_SECRET=');
    expect(r.fs.files.get('/tmp/instances/aaaaaa/docker-compose.yml')).toBeUndefined();
  });

  it('generates a four-digit owner PIN', async () => {
    const r = makeDeps();
    const result = await provision(makeContext(), r.deps);

    expect(String(result.output.pin)).toMatch(/^\d{4}$/);
  });

  it('passes the PIN as a discrete argument, never inside a URL', async () => {
    const r = makeDeps();
    const result = await provision(makeContext(), r.deps);

    const ownerCmd = r.commands.find((c) => c.includes('create-owner'));
    expect(ownerCmd).toContain(String(result.output.pin));
    expect(ownerCmd).toContain('254712345678');
  });
});

describe('summarise', () => {
  it('reports progress for the onboarding screen', () => {
    const s = summarise([
      { key: 'validate', displayName: 'a', position: 1, customerVisible: true, status: 'SUCCEEDED' },
      { key: 'instance_id', displayName: 'b', position: 2, customerVisible: true, status: 'RUNNING' },
    ]);
    expect(s.completed).toBe(1);
    expect(s.percent).toBe(50);
    expect(s.currentLabel).toBe('b');
  });

  it('hides infrastructure steps from the customer', () => {
    const keys = customerVisibleSteps().map((s) => s.key);
    expect(keys).not.toContain('redis');
    expect(keys).not.toContain('migrations');
    expect(keys).toContain('postgres');
    expect(keys[0]).toBe('validate');
  });
});
