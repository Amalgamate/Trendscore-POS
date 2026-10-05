import type { PaymentState } from './states.js';

/** Money is a string of minor-unit-safe decimal. Never a JS float. */
export type Money = string;

export type PaymentMethod = 'CASH' | 'MPESA' | 'CREDIT' | 'BANK';

export interface ProcessPaymentRequest {
  /**
   * Our idempotency key. Sent to Daraja as MerchantReconciliationID and
   * UNIQUE in the database, so a replayed callback can never double-credit.
   */
  idempotencyKey: string;
  amount: Money;
  currency: 'KES';
  /** Customer M-Pesa number in 2547XXXXXXXX form. */
  msisdn: string;
  /** e.g. "Subscription renewal" or receipt number. */
  description: string;
  /** Shop instance this charge belongs to, for reconciliation reports. */
  reference: string;
}

export interface ProcessPaymentResult {
  provider: PaymentMethod;
  state: PaymentState;
  idempotencyKey: string;
  /** Provider handle for status queries: CheckoutRequestID for M-Pesa. */
  providerReference?: string;
  receiptNumber?: string;
  amount: Money;
  msisdn: string;
  initiatedAt: Date;
  settledAt?: Date;
  resultCode?: string;
  resultDescription?: string;
}

export interface QueryStatusRequest {
  idempotencyKey: string;
  providerReference?: string;
}

export type CallbackVerification = 'verified' | 'unverifiable' | 'rejected';

/**
 * Implemented by cash, M-Pesa, credit and (later) card providers.
 *
 * The POS only ever calls processPayment(). It has no idea which provider
 * handles the request, so adding a provider never touches the UI.
 */
export interface PaymentProvider {
  readonly method: PaymentMethod;
  processPayment(req: ProcessPaymentRequest): Promise<ProcessPaymentResult>;
  queryStatus(req: QueryStatusRequest): Promise<ProcessPaymentResult | null>;
  /**
   * Verify an inbound webhook is genuinely from the provider.
   * Daraja does not sign callbacks, so this validates structure, the
   * known checkout ID, and that the amount matches what we recorded.
   */
  verifyCallback(payload: unknown): CallbackVerification;
  /** Expressed in minor units to avoid float comparison. */
  supportsAmount(amount: Money): boolean;
}

export class PaymentError extends Error {
  constructor(
    message: string,
    readonly code: string,
    readonly retryable = false,
  ) {
    super(message);
    this.name = 'PaymentError';
  }
}

/** Normalise Kenyan phone input to 2547XXXXXXXX. */
export function normaliseMsisdn(input: string): string {
  const digits = input.replace(/[^\d]/g, '');
  if (digits.startsWith('254')) return digits;
  if (digits.startsWith('0')) return `254${digits.slice(1)}`;
  if (digits.startsWith('7') && digits.length === 9) return `254${digits}`;
  throw new PaymentError(`Invalid M-Pesa number: ${input}`, 'INVALID_MSIMDN');
}

export function isValidMsisdn(input: string): boolean {
  try {
    normaliseMsisdn(input);
    return true;
  } catch {
    return false;
  }
}
