import { describe, expect, it } from 'vitest';
import { runHealthChecks } from '../src/modules/health/health';

describe('health checks', () => {
  it('reports healthy when every probe passes', async () => {
    const result = await runHealthChecks({
      postgres: async () => undefined,
      redis: async () => undefined,
    });
    expect(result.status).toBe('healthy');
    expect(result.checks.postgres?.status).toBe('up');
    expect(result.checks.redis?.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it('degrades instead of failing when a dependency is down', async () => {
    // Critical: a transient Postgres blip must not make the provisioner
    // tear down a shop that is otherwise trading.
    const result = await runHealthChecks({
      postgres: async () => {
        throw new Error('ECONNREFUSED');
      },
      redis: async () => undefined,
    });
    expect(result.status).toBe('degraded');
    expect(result.checks.postgres?.status).toBe('down');
    expect(result.checks.postgres?.error).toContain('ECONNREFUSED');
    expect(result.checks.redis?.status).toBe('up');
  });

  it('is healthy with no probes configured yet', async () => {
    const result = await runHealthChecks({});
    expect(result.status).toBe('healthy');
  });

  it('reports uptime and version for the control-plane health view', async () => {
    const result = await runHealthChecks({}, { version: '1.2.3', startedAt: Date.now() - 5000 });
    expect(result.version).toBe('1.2.3');
    expect(result.uptimeSeconds).toBeGreaterThanOrEqual(4);
  });

  it('handles a non-Error throw without crashing', async () => {
    const result = await runHealthChecks({
      flaky: async () => {
        throw 'string failure';
      },
    });
    expect(result.checks.flaky?.status).toBe('down');
    expect(result.checks.flaky?.error).toBe('unknown error');
  });
});
