/**
 * Payment state machine.
 *
 * The central design decision of this file: TIMEOUT and UNKNOWN are NOT
 * terminal failures.
 *
 * When a customer does not enter their M-Pesa PIN, Daraja reports a
 * timeout — but the funds can still settle afterwards. Treating a timeout
 * as "failed" means we hand back goods for money that later arrives, or
 * vice versa. So:
 *
 *   - UNKNOWN  = we do not yet know. Reconcile, do not guess.
 *   - TIMEOUT  = the prompt window elapsed. Still reconcile for 24h.
 *
 * Only SUCCESS and FAILED are genuinely settled. A late-arriving success
 * on a settled-failed payment must be handled by a reversing entry, never
 * by mutating the original record (see reconcile.ts).
 */

/** Daraja ResultCode values that mean the customer actually paid. */
export const DARajaResultCode = {
  SUCCESS: '0',
  /** Insufficient balance — a real, settled failure. */
  INSUFFICIENT_FUNDS: '1037',
  /** Simulated only. */
  SIMULATED: '0',
} as const;

export type PaymentState =
  | 'INITIATED'
  | 'PROMPT_SENT'
  | 'WAITING'
  | 'SUCCESS'
  | 'FAILED'
  | 'CANCELLED'
  | 'TIMEOUT'
  | 'UNKNOWN';

/**
 * Terminal states. Reaching one of these means we stop polling.
 * Deliberately excludes TIMEOUT and UNKNOWN.
 */
export const TERMINAL_STATES: ReadonlySet<PaymentState> = new Set<PaymentState>([
  'SUCCESS',
  'FAILED',
  'CANCELLED',
]);

/** States that require background reconciliation before we can conclude. */
export const RECONCILABLE_STATES: ReadonlySet<PaymentState> = new Set<PaymentState>([
  'TIMEOUT',
  'UNKNOWN',
  'WAITING',
]);

/** Whether the customer should keep waiting on screen. */
export const IN_FLIGHT_STATES: ReadonlySet<PaymentState> = new Set<PaymentState>([
  'PROMPT_SENT',
  'WAITING',
]);

const ALLOWED: Readonly<Record<PaymentState, readonly PaymentState[]>> = {
  INITIATED: ['PROMPT_SENT', 'FAILED', 'UNKNOWN'],
  PROMPT_SENT: ['WAITING', 'SUCCESS', 'FAILED', 'TIMEOUT', 'UNKNOWN', 'CANCELLED'],
  WAITING: ['SUCCESS', 'FAILED', 'TIMEOUT', 'UNKNOWN', 'CANCELLED'],
  TIMEOUT: ['SUCCESS', 'FAILED', 'UNKNOWN', 'CANCELLED'],
  UNKNOWN: ['SUCCESS', 'FAILED', 'TIMEOUT', 'CANCELLED'],
  SUCCESS: [],
  FAILED: ['UNKNOWN'],
  CANCELLED: [],
};

export function canTransition(from: PaymentState, to: PaymentState): boolean {
  return ALLOWED[from]?.includes(to) ?? false;
}

export function isTerminal(state: PaymentState): boolean {
  return TERMINAL_STATES.has(state);
}

export function needsReconciliation(state: PaymentState): boolean {
  return RECONCILABLE_STATES.has(state);
}

export class InvalidTransitionError extends Error {
  constructor(
    readonly from: PaymentState,
    readonly to: PaymentState,
  ) {
    super(`Illegal payment transition: ${from} -> ${to}`);
    this.name = 'InvalidTransitionError';
  }
}

/**
 * Apply a transition, refusing illegal moves.
 *
 * The FAILED -> UNKNOWN edge exists for a specific case: we wrote FAILED,
 * then reconciliation proved otherwise. We do not jump straight to SUCCESS
 * because the record must pass back through UNKNOWN for auditability.
 */
export function transition(from: PaymentState, to: PaymentState): PaymentState {
  if (!canTransition(from, to)) throw new InvalidTransitionError(from, to);
  return to;
}

/** Map a Daraja ResultCode onto our state vocabulary. */
export function stateFromResultCode(resultCode: string): PaymentState {
  switch (resultCode) {
    case DARajaResultCode.SUCCESS:
      return 'SUCCESS';
    case DARajaResultCode.INSUFFICIENT_FUNDS:
      return 'FAILED';
    default:
      // 1 = insufficient funds variants, 1032=timeout, 1036=DS timeout,
      // 2002=declined, 2006=suspended. All of these mean "not settled",
      // and several can still resolve later.
      return 'UNKNOWN';
  }
}

/** Customer-facing copy. Never surface a raw ResultCode to a shop owner. */
export function describeState(state: PaymentState): string {
  switch (state) {
    case 'INITIATED':
      return 'Preparing payment';
    case 'PROMPT_SENT':
      return 'Check your phone';
    case 'WAITING':
      return 'Waiting for customer';
    case 'SUCCESS':
      return 'Payment received';
    case 'FAILED':
      return 'Payment failed';
    case 'CANCELLED':
      return 'Payment cancelled';
    case 'TIMEOUT':
      return 'Still confirming — this can take a few minutes';
    case 'UNKNOWN':
      return 'Confirming payment status';
  }
}
