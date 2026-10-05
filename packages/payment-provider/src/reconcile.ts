import {
  isTerminal,
  needsReconciliation,
  type PaymentState,
} from './states.js';
import type { ProcessPaymentResult } from './types.js';

export interface ReconcileDecision {
  action: 'none' | 'apply_success' | 'apply_failure' | 'write_reversal' | 'keep_polling';
  reason: string;
}

/**
 * Consecutive contradictory reads tolerated before we escalate.
 *
 * A single disagreeing read against a recorded SUCCESS is far more likely
 * to be a glitch than a genuine clawed-back settlement, so we re-query a
 * few times before touching the ledger.
 */
export const CONTRADICTION_THRESHOLD = 3;

/**
 * Decide what to do when a provider reports a late result.
 *
 * The dangerous case: we already recorded FAILED (or TIMEOUT) and told the
 * customer their payment failed, but the money actually settled. We must
 * NOT silently flip the record to SUCCESS — the customer may have already
 * taken the goods and walked out, and a cashier may have voided the sale.
 *
 * Instead we append a reversing entry and a new settlement record. The
 * audit trail shows both the original decision and the correction. That is
 * the "nothing goes untracked" principle surviving contact with M-Pesa.
 *
 * Rules, in order:
 *   1. Agreement            -> none
 *   2. Recorded SUCCESS     -> keep_polling until the contradiction persists,
 *                             then write_reversal. Never silently flip money
 *                             that was already handed to the customer.
 *   3. Late SUCCESS, nothing settled -> apply_success
 *   4. Definitive failure, nothing settled -> apply_failure
 *   5. Anything else        -> keep_polling
 */
export function decideReconcile(
  recorded: ProcessPaymentResult,
  reported: ProcessPaymentResult,
  consecutiveMismatches = 1,
): ReconcileDecision {
  if (reported.state === recorded.state) {
    return { action: 'none', reason: 'States match' };
  }

  // Rule 2: we told the customer they paid. Reversing that needs certainty.
  if (recorded.state === 'SUCCESS') {
    if (consecutiveMismatches >= CONTRADICTION_THRESHOLD) {
      return {
        action: 'write_reversal',
        reason: `Provider contradicted a recorded success ${consecutiveMismatches}x — reversing with audit entry`,
      };
    }
    return {
      action: 'keep_polling',
      reason: 'Recorded success contradicted by provider — re-query before acting',
    };
  }

  const wasInFlight =
    !isTerminal(recorded.state) || needsReconciliation(recorded.state);

  // Rule 3: a success arriving for something we had not settled is clean.
  if (reported.state === 'SUCCESS') {
    if (wasInFlight) {
      return { action: 'apply_success', reason: 'Late success on a non-settled payment' };
    }
    return {
      action: 'write_reversal',
      reason: 'Success reported after we already recorded a settled failure',
    };
  }

  // Rule 4: a definitive failure on something still in flight.
  if (reported.state === 'FAILED' || reported.state === 'CANCELLED') {
    if (wasInFlight) {
      return { action: 'apply_failure', reason: 'Definitive failure from provider' };
    }
    return {
      action: 'keep_polling',
      reason: 'Failure on an already-settled payment — re-query before acting',
    };
  }

  // Rule 5
  return { action: 'keep_polling', reason: `Provider reports ${reported.state}` };
}

/**
 * Poll window. A timed-out M-Pesa prompt can settle well past the point the
 * customer gave up. 24 hours covers the observed Daraja settlement tail.
 */
export const RECONCILE_WINDOW_HOURS = 24;

/** Whether we should still poll this payment. */
export function shouldKeepPolling(state: PaymentState, ageMs: number): boolean {
  if (isTerminal(state)) return false;
  if (!needsReconciliation(state)) return false;
  return ageMs < RECONCILE_WINDOW_HOURS * 60 * 60 * 1000;
}

/**
 * Backoff schedule for reconciliation polls. Aggressive at first, then
 * sparse — a settled payment surfaces within seconds, a genuinely dead one
 * should not cost 200 API calls over 24 hours.
 */
export function nextPollDelayMs(attempt: number): number {
  const schedule = [
    5_000, 15_000, 30_000, 60_000, 5 * 60_000, 15 * 60_000, 30 * 60_000, 60 * 60_000,
  ];
  return schedule[Math.min(attempt, schedule.length - 1)] ?? 60 * 60_000;
}
