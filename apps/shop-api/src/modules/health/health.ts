/**
 * Health endpoint.
 *
 * The provisioning engine polls this before marking an instance READY, and
 * the control plane surfaces it in the instance health view. It must answer
 * fast and must not require authentication — Traefik reaches it directly.
 *
 * A failing dependency reports DEGRADED rather than failing outright, so a
 * transient Postgres blip does not make us tear down a working shop.
 */
import type { Request, Response } from 'express';

export interface HealthCheckResult {
  status: 'healthy' | 'degraded' | 'unhealthy';
  checks: Record<string, { status: 'up' | 'down'; latencyMs?: number; error?: string }>;
  version?: string;
  uptimeSeconds?: number;
}

type Probe = () => Promise<void>;

export async function runHealthChecks(
  probes: Record<string, Probe>,
  meta: { version?: string; startedAt?: number } = {},
): Promise<HealthCheckResult> {
  const checks: HealthCheckResult['checks'] = {};

  await Promise.all(
    Object.entries(probes).map(async ([name, probe]) => {
      const startedAt = Date.now();
      try {
        await probe();
        checks[name] = { status: 'up', latencyMs: Date.now() - startedAt };
      } catch (error) {
        checks[name] = {
          status: 'down',
          latencyMs: Date.now() - startedAt,
          error: error instanceof Error ? error.message : 'unknown error',
        };
      }
    }),
  );

  const down = Object.values(checks).filter((c) => c.status === 'down');

  return {
    // Anything down is degraded, not unhealthy: we would rather keep
    // serving than have the provisioner tear down a live shop.
    status: down.length === 0 ? 'healthy' : 'degraded',
    checks,
    version: meta.version,
    uptimeSeconds: meta.startedAt ? Math.round((Date.now() - meta.startedAt) / 1000) : undefined,
  };
}

export function healthHandler(
  probes: Record<string, Probe>,
  meta: { version?: string; startedAt: number },
) {
  return async (_req: Request, res: Response): Promise<void> => {
    const result = await runHealthChecks(probes, meta);
    // Always 200: the process is up and reachable. Degradation is reported
    // in the body so the provisioner does not tear down a working shop
    // over a transient database blip.
    res.status(200).json(result);
  };
}
