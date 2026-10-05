import { orderedSteps } from './steps.js';
import type {
  ProvisioningContext,
  ProvisioningDeps,
  StepDefinition,
  StepKey,
  StepRecord,
  StepStatus,
} from './types.js';

export interface ProvisioningResult {
  status: 'SUCCEEDED' | 'FAILED';
  steps: StepRecord[];
  failedStep?: StepKey;
  error?: string;
  /** Artefacts worth persisting: hostname, generated PIN, instance id. */
  output: Record<string, unknown>;
}

export interface RunOptions {
  /**
   * Steps already SUCCEEDED from a previous attempt. They are skipped, so
   * an owner who refreshes the onboarding page resumes rather than
   * rebuilding their shop from scratch.
   */
  resumeFrom?: StepRecord[];
  /** Roll back completed steps when one fails. Default true. */
  rollbackOnFailure?: boolean;
  /** Stop after this step. Used by tests to isolate one stage. */
  until?: StepKey;
}

/**
 * Run the provisioning workflow.
 *
 * Deliberately sequential. A shop instance is a small amount of work, and
 * parallel steps would make partial-failure states harder to reason about
 * and to resume than they are already.
 */
export async function provision(
  ctx: ProvisioningContext,
  deps: ProvisioningDeps,
  options: RunOptions = {},
): Promise<ProvisioningResult> {
  const steps = orderedSteps();
  const rollbackOnFailure = options.rollbackOnFailure ?? true;
  const alreadyDone = new Map(
    (options.resumeFrom ?? [])
      .filter((s) => s.status === 'SUCCEEDED')
      .map((s) => [s.key, s]),
  );

  const records: StepRecord[] = [];
  const output: Record<string, unknown> = {};
  const completed: StepDefinition[] = [];

  for (const step of steps) {
    const prior = alreadyDone.get(step.key);
    if (prior) {
      const resumed: StepRecord = { ...prior, status: 'SUCCEEDED' };
      records.push(resumed);
      if (resumed.data) Object.assign(output, resumed.data);
      await deps.onStepChange?.(step.key, 'SUCCEEDED', resumed.message);
      deps.log('info', `Resumed step ${step.key}`, { status: 'SUCCEEDED' });
      if (options.until === step.key) break;
      continue;
    }

    const record: StepRecord = {
      key: step.key,
      displayName: step.displayName,
      position: step.position,
      customerVisible: step.customerVisible,
      status: 'RUNNING',
      startedAt: new Date(),
    };
    records.push(record);
    await deps.onStepChange?.(step.key, 'RUNNING');
    deps.log('info', `Running step ${step.key}`, { position: step.position });

    try {
      const outcome = await step.execute(ctx, deps);
      record.status = 'SUCCEEDED';
      record.message = outcome.message;
      record.data = outcome.data;
      record.finishedAt = new Date();
      if (outcome.data) Object.assign(output, outcome.data);
      completed.push(step);
      await deps.onStepChange?.(step.key, 'SUCCEEDED', outcome.message);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      record.status = 'FAILED';
      record.errorDetail = message;
      record.finishedAt = new Date();
      await deps.onStepChange?.(step.key, 'FAILED', message);
      deps.log('error', `Step ${step.key} failed`, { error: message });

      if (rollbackOnFailure) {
        await rollback(completed, ctx, deps);
      }

      return {
        status: 'FAILED',
        steps: records,
        failedStep: step.key,
        error: message,
        output,
      };
    }

    if (options.until === step.key) break;
  }

  return { status: 'SUCCEEDED', steps: records, output };
}

/**
 * Undo completed steps in reverse order.
 *
 * Best-effort by design: a rollback failure must not mask the original
 * provisioning error, which is the thing support actually needs to see.
 */
async function rollback(
  completed: StepDefinition[],
  ctx: ProvisioningContext,
  deps: ProvisioningDeps,
): Promise<void> {
  for (const step of [...completed].reverse()) {
    if (!step.rollback) continue;
    try {
      await step.rollback(ctx, deps);
      deps.log('info', `Rolled back step ${step.key}`);
    } catch (error) {
      deps.log('warn', `Rollback of ${step.key} failed`, {
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}

/** Progress summary for the onboarding screen. */
export function summarise(records: StepRecord[]): {
  total: number;
  completed: number;
  percent: number;
  currentLabel: string | null;
  failedLabel: string | null;
} {
  const total = records.length;
  const completed = records.filter((r) => r.status === 'SUCCEEDED').length;
  const failed = records.find((r) => r.status === 'FAILED');
  const running = records.find((r) => r.status === 'RUNNING');

  return {
    total,
    completed,
    percent: total === 0 ? 0 : Math.round((completed / total) * 100),
    currentLabel: running?.displayName ?? null,
    failedLabel: failed?.displayName ?? null,
  };
}

/** The steps a shop owner is allowed to see, in order. */
export function customerVisibleSteps(): StepRecord[] {
  return orderedSteps()
    .filter((s) => s.customerVisible)
    .map((s) => ({
      key: s.key,
      displayName: s.displayName,
      position: s.position,
      customerVisible: true,
      status: 'PENDING' as StepStatus,
    }));
}
