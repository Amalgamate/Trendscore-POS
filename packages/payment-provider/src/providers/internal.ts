import {
  type CallbackVerification,
  type Money,
  type ProcessPaymentRequest,
  type ProcessPaymentResult,
  type PaymentProvider,
  PaymentError,
} from '../types.js';

/**
 * Cash settles synchronously — the money is physically in the drawer.
 * Still modelled as a provider so the POS has one uniform call path.
 */
export class CashProvider implements PaymentProvider {
  readonly method = 'CASH' as const;
  private readonly now: () => Date;

  constructor(opts: { now?: () => Date } = {}) {
    this.now = opts.now ?? (() => new Date());
  }

  supportsAmount(amount: Money): boolean {
    const n = Number(amount);
    return Number.isFinite(n) && n > 0;
  }

  async processPayment(req: ProcessPaymentRequest): Promise<ProcessPaymentResult> {
    if (!this.supportsAmount(req.amount)) {
      throw new PaymentError('Amount must be greater than zero', 'INVALID_AMOUNT');
    }
    const at = this.now();
    return {
      provider: 'CASH',
      state: 'SUCCESS',
      idempotencyKey: req.idempotencyKey,
      amount: req.amount,
      msisdn: '',
      initiatedAt: at,
      settledAt: at,
      receiptNumber: `CASH-${req.idempotencyKey.slice(0, 8).toUpperCase()}`,
    };
  }

  async queryStatus(): Promise<ProcessPaymentResult | null> {
    // Cash has no asynchronous lifecycle.
    return null;
  }

  verifyCallback(): CallbackVerification {
    return 'rejected';
  }
}

/**
 * Credit sale. Settles immediately at the POS but creates a customer
 * ledger obligation — the money is owed, not received.
 *
 * The limit check is enforced by the shop service inside the same
 * database transaction as the sale, not here, so the balance cannot
 * change between the check and the write.
 */
export class CreditProvider implements PaymentProvider {
  readonly method = 'CREDIT' as const;

  supportsAmount(amount: Money): boolean {
    const n = Number(amount);
    return Number.isFinite(n) && n > 0;
  }

  async processPayment(req: ProcessPaymentRequest): Promise<ProcessPaymentResult> {
    if (!this.supportsAmount(req.amount)) {
      throw new PaymentError('Amount must be greater than zero', 'INVALID_AMOUNT');
    }
    const at = new Date();
    return {
      provider: 'CREDIT',
      state: 'SUCCESS',
      idempotencyKey: req.idempotencyKey,
      amount: req.amount,
      msisdn: '',
      initiatedAt: at,
      settledAt: at,
      resultDescription: 'Recorded against customer ledger',
    };
  }

  async queryStatus(): Promise<ProcessPaymentResult | null> {
    return null;
  }

  verifyCallback(): CallbackVerification {
    return 'rejected';
  }
}
