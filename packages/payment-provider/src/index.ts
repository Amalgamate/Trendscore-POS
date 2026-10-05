/**
 * @retail-os/payment-provider
 *
 * One abstraction for every payment method. The POS calls processPayment()
 * and never learns which provider handled it.
 *
 * The M-Pesa state machine deliberately models TIMEOUT and UNKNOWN as
 * non-terminal, because a timed-out prompt can still settle. See
 * ./states.ts and ./reconcile.ts — read those before touching billing.
 */

export {
  type PaymentState,
  TERMINAL_STATES,
  RECONCILABLE_STATES,
  IN_FLIGHT_STATES,
  DARajaResultCode,
  canTransition,
  isTerminal,
  needsReconciliation,
  transition,
  stateFromResultCode,
  describeState,
  InvalidTransitionError,
} from './states.js';

export {
  type Money,
  type PaymentMethod,
  type ProcessPaymentRequest,
  type ProcessPaymentResult,
  type QueryStatusRequest,
  type CallbackVerification,
  type PaymentProvider,
  PaymentError,
  normaliseMsisdn,
  isValidMsisdn,
} from './types.js';

export { PaymentRegistry } from './registry.js';

export {
  RECONCILE_WINDOW_HOURS,
  CONTRADICTION_THRESHOLD,
  decideReconcile,
  shouldKeepPolling,
  nextPollDelayMs,
  type ReconcileDecision,
} from './reconcile.js';

export { FakeMpesaProvider, type FakeScenario } from './providers/fake-mpesa.js';
export { CashProvider, CreditProvider } from './providers/internal.js';
