export type MpesaEnvironment = 'sandbox' | 'production';

export type MpesaTransactionState =
  | 'PENDING'
  | 'SUCCESS'
  | 'FAILED'
  | 'CANCELLED'
  | 'UNKNOWN';

export interface MpesaCredentials {
  consumerKey: string;
  consumerSecret: string;
  shortcode: string;
  passkey: string;
  environment: MpesaEnvironment;
  transactionType: 'CustomerPayBillOnline' | 'CustomerBuyGoodsOnline';
}

export interface MpesaStkPushRequest {
  idempotencyKey: string;
  amount: string;
  phoneNumber: string;
  accountReference: string;
  transactionDescription: string;
  callbackUrl: string;
}

export interface MpesaStkPushResult {
  checkoutRequestId: string;
  merchantRequestId: string;
  responseCode: string;
  responseDescription: string;
  customerMessage?: string;
}

export interface MpesaTransactionQuery {
  checkoutRequestId: string;
}

export interface MpesaTransactionQueryResult {
  resultCode: string;
  resultDescription: string;
}

export interface MpesaCallbackResult {
  checkoutRequestId: string;
  merchantRequestId?: string;
  resultCode: string;
  resultDescription: string;
  receiptNumber?: string;
  amount?: string;
  phoneNumber?: string;
  transactionDate?: string;
}

/**
 * Boundary for the future Safaricom Daraja adapter.
 *
 * Implementations must be server-only, persist credentials using the approved
 * secret store, enforce idempotency, and treat callbacks as untrusted until
 * correlated with a recorded request and validated amount.
 */
export interface MpesaDarajaAdapter {
  initiateStkPush(
    credentials: MpesaCredentials,
    request: MpesaStkPushRequest,
  ): Promise<MpesaStkPushResult>;
  queryTransaction(
    credentials: MpesaCredentials,
    query: MpesaTransactionQuery,
  ): Promise<MpesaTransactionQueryResult>;
  parseCallback(payload: unknown): MpesaCallbackResult | null;
}
