import {
  type CallbackVerification,
  type Money,
  type ProcessPaymentRequest,
  type ProcessPaymentResult,
  type PaymentProvider,
  PaymentError,
} from '../types.js';
import { type PaymentState, transition } from '../states.js';

/**
 * Deterministic fake M-Pesa provider.
 *
 * Safaricom sandbox is unreliable and Daraja production approval takes
 * weeks. Every local test and developer machine runs on this instead, so
 * the team is never blocked and behaviour stays deterministic.
 *
 * Scenario is chosen by the msisdn suffix so tests read clearly:
 *   ...001  -> SUCCESS
 *   ...002  -> immediate FAILED (insufficient funds)
 *   ...003  -> TIMEOUT that later settles (the dangerous real-world case)
 *   ...004  -> stays UNKNOWN (customer walked away; needs reconciliation)
 *   ...005  -> CANCELLED by customer
 *   default -> SUCCESS
 */
export type FakeScenario = 'SUCCESS' | 'FAILED' | 'LATE_SETTLE' | 'UNKNOWN' | 'CANCELLED';

export interface FakeMpesaOptions {
  /** Simulated clock, for deterministic tests. */
  now?: () => Date;
  /** Idempotency keys already processed; enforces replay protection. */
  seen?: Set<string>;
}

export class FakeMpesaProvider implements PaymentProvider {
  readonly method = 'MPESA' as const;

  private readonly now: () => Date;
  private readonly seen: Set<string>;
  /** Stores every result so queryStatus can resolve later states. */
  private readonly records = new Map<string, ProcessPaymentResult>();
  /** Which scenario each payment will follow, for deterministic tests. */
  private readonly scenarios = new Map<string, FakeScenario>();

  constructor(opts: FakeMpesaOptions = {}) {
    this.now = opts.now ?? (() => new Date());
    this.seen = opts.seen ?? new Set<string>();
  }

  supportsAmount(amount: Money): boolean {
    const n = Number(amount);
    if (!Number.isFinite(n) || n <= 0) return false;
    // Daraja STK push caps a single request at KES 70,000.
    return n <= 70_000;
  }

  async processPayment(req: ProcessPaymentRequest): Promise<ProcessPaymentResult> {
    if (!this.supportsAmount(req.amount)) {
      throw new PaymentError('Amount out of range for M-Pesa', 'AMOUNT_OUT_OF_RANGE');
    }

    // Replay guard: same key returns the original result, never a new charge.
    const existing = this.records.get(req.idempotencyKey);
    if (existing) return existing;
    if (this.seen.has(req.idempotencyKey)) {
      throw new PaymentError('Duplicate idempotency key', 'DUPLICATE_KEY', true);
    }

    const scenario = this.scenarioFor(req.msisdn);

    const base: ProcessPaymentResult = {
      provider: 'MPESA',
      state: 'PROMPT_SENT',
      idempotencyKey: req.idempotencyKey,
      providerReference: `COID_${this.checksum(req.idempotencyKey)}_X`,
      amount: req.amount,
      msisdn: req.msisdn,
      initiatedAt: this.now(),
    };

    this.records.set(req.idempotencyKey, base);
    this.scenarios.set(req.idempotencyKey, scenario);
    this.seen.add(req.idempotencyKey);
    return base;
  }

  /** The scenario chosen for a payment, so tests can drive it deterministically. */
  scenarioOf(idempotencyKey: string): FakeScenario | undefined {
    return this.scenarios.get(idempotencyKey);
  }

  /**
   * Resolve a prompt the way Daraja's callback eventually would.
   * Called by the callback handler or the reconciliation job.
   */
  resolve(
    idempotencyKey: string,
    state: Extract<PaymentState, 'SUCCESS' | 'FAILED' | 'CANCELLED' | 'TIMEOUT'>,
  ): ProcessPaymentResult {
    const current = this.records.get(idempotencyKey);
    if (!current) {
      throw new PaymentError(`Unknown idempotency key ${idempotencyKey}`, 'UNKNOWN_KEY');
    }
    const next = transition(current.state, state);
    const updated: ProcessPaymentResult = {
      ...current,
      state: next,
      resultCode: next === 'SUCCESS' ? '0' : 'FAKE',
      resultDescription: `Simulated ${next}`,
      receiptNumber: next === 'SUCCESS' ? this.receiptFor(idempotencyKey) : undefined,
      settledAt: next === 'SUCCESS' || next === 'FAILED' ? this.now() : undefined,
    };
    this.records.set(idempotencyKey, updated);
    return updated;
  }

  async queryStatus(req: {
    idempotencyKey: string;
  }): Promise<ProcessPaymentResult | null> {
    return this.records.get(req.idempotencyKey) ?? null;
  }

  verifyCallback(payload: unknown): CallbackVerification {
    if (typeof payload !== 'object' || payload === null) return 'rejected';
    const p = payload as Record<string, unknown>;
    const hasCheckout = typeof p.CheckoutRequestID === 'string';
    const hasResult = typeof p.ResultCode === 'string';
    if (!hasCheckout && !hasResult) return 'rejected';
    const key = this.keyFromCallback(p);
    return key && this.records.has(key) ? 'verified' : 'unverifiable';
  }

  private keyFromCallback(p: Record<string, unknown>): string | undefined {
    const id = p.MerchantReconciliationID;
    return typeof id === 'string' ? id : undefined;
  }

  private scenarioFor(msisdn: string): FakeScenario {
    const scenarios: FakeScenario[] = [
      'SUCCESS',
      'FAILED',
      'LATE_SETTLE',
      'UNKNOWN',
      'CANCELLED',
    ];
    const last = msisdn.slice(-3);
    const n = Number(last);
    return scenarios[n - 1] ?? 'SUCCESS';
  }

  private checksum(input: string): string {
    let h = 0;
    for (let i = 0; i < input.length; i++) h = (h * 31 + input.charCodeAt(i)) >>> 0;
    return h.toString(36).toUpperCase().slice(0, 8);
  }

  private receiptFor(key: string): string {
    return `FK${this.checksum(key).padStart(8, '0').slice(0, 8)}`;
  }
}
