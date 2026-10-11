import type {
  MpesaCallbackResult,
  MpesaCredentials,
  MpesaDarajaAdapter,
  MpesaStkPushRequest,
  MpesaStkPushResult,
  MpesaTransactionQuery,
  MpesaTransactionQueryResult,
} from './mpesa.contract';

type JsonRecord = Record<string, unknown>;

export class MpesaProviderError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly providerCode?: string,
  ) {
    super(message);
  }
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requiredString(record: JsonRecord, key: string): string {
  const value = record[key];
  if (typeof value !== 'string' || value.length === 0) {
    throw new MpesaProviderError('Daraja returned an invalid response.', false);
  }
  return value;
}

function timestampNairobi(date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Africa/Nairobi',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  const part = (type: string) => parts.find((value) => value.type === type)?.value;
  return `${part('year')}${part('month')}${part('day')}${part('hour')}${part('minute')}${part('second')}`;
}

export class DarajaMpesaAdapter implements MpesaDarajaAdapter {
  private baseUrl(environment: MpesaCredentials['environment']): string {
    return environment === 'production'
      ? 'https://api.safaricom.co.ke'
      : 'https://sandbox.safaricom.co.ke';
  }

  private async requestJson(
    url: string,
    init: RequestInit,
  ): Promise<JsonRecord> {
    let response: Response;
    try {
      response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(12_000),
      });
    } catch {
      throw new MpesaProviderError(
        'Daraja could not be reached. The payment result may be uncertain.',
        true,
      );
    }
    let body: unknown;
    try {
      body = await response.json();
    } catch {
      throw new MpesaProviderError(
        'Daraja returned an unreadable response.',
        response.status >= 500,
      );
    }
    if (!isRecord(body)) {
      throw new MpesaProviderError(
        'Daraja returned an invalid response.',
        response.status >= 500,
      );
    }
    if (!response.ok) {
      const code =
        typeof body['errorCode'] === 'string' ? body['errorCode'] : undefined;
      throw new MpesaProviderError(
        'Daraja rejected the request. Check the M-Pesa configuration and try again.',
        response.status >= 500 || response.status === 429,
        code,
      );
    }
    return body;
  }

  private async accessToken(credentials: MpesaCredentials): Promise<string> {
    const authorization = Buffer.from(
      `${credentials.consumerKey}:${credentials.consumerSecret}`,
    ).toString('base64');
    const response = await this.requestJson(
      `${this.baseUrl(credentials.environment)}/oauth/v1/generate?grant_type=client_credentials`,
      { headers: { Authorization: `Basic ${authorization}` } },
    );
    return requiredString(response, 'access_token');
  }

  async testConnection(credentials: MpesaCredentials): Promise<void> {
    await this.accessToken(credentials);
  }

  async initiateStkPush(
    credentials: MpesaCredentials,
    request: MpesaStkPushRequest,
  ): Promise<MpesaStkPushResult> {
    const timestamp = timestampNairobi();
    const password = Buffer.from(
      `${credentials.shortcode}${credentials.passkey}${timestamp}`,
    ).toString('base64');
    const token = await this.accessToken(credentials);
    const body = await this.requestJson(
      `${this.baseUrl(credentials.environment)}/mpesa/stkpush/v1/processrequest`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          BusinessShortCode: credentials.shortcode,
          Password: password,
          Timestamp: timestamp,
          TransactionType: credentials.transactionType,
          Amount: Number(request.amount),
          PartyA: request.phoneNumber.replace(/\D/g, ''),
          PartyB: credentials.shortcode,
          PhoneNumber: request.phoneNumber.replace(/\D/g, ''),
          CallBackURL: request.callbackUrl,
          AccountReference: request.accountReference,
          TransactionDesc: request.transactionDescription,
        }),
      },
    );
    return {
      checkoutRequestId: requiredString(body, 'CheckoutRequestID'),
      merchantRequestId: requiredString(body, 'MerchantRequestID'),
      responseCode: requiredString(body, 'ResponseCode'),
      responseDescription: requiredString(body, 'ResponseDescription'),
      ...(typeof body['CustomerMessage'] === 'string'
        ? { customerMessage: body['CustomerMessage'] }
        : {}),
    };
  }

  async queryTransaction(
    credentials: MpesaCredentials,
    query: MpesaTransactionQuery,
  ): Promise<MpesaTransactionQueryResult> {
    const timestamp = timestampNairobi();
    const password = Buffer.from(
      `${credentials.shortcode}${credentials.passkey}${timestamp}`,
    ).toString('base64');
    const token = await this.accessToken(credentials);
    const body = await this.requestJson(
      `${this.baseUrl(credentials.environment)}/mpesa/stkpushquery/v1/query`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          BusinessShortCode: credentials.shortcode,
          Password: password,
          Timestamp: timestamp,
          CheckoutRequestID: query.checkoutRequestId,
        }),
      },
    );
    return {
      resultCode: requiredString(body, 'ResultCode'),
      resultDescription: requiredString(body, 'ResultDesc'),
    };
  }

  parseCallback(payload: unknown): MpesaCallbackResult | null {
    if (!isRecord(payload) || !isRecord(payload['Body'])) return null;
    const stk = payload['Body']['stkCallback'];
    if (!isRecord(stk)) return null;
    const callbackMetadata = stk['CallbackMetadata'];
    const callbackItems = isRecord(callbackMetadata)
      ? callbackMetadata['Item']
      : undefined;
    if (!Array.isArray(callbackItems)) {
      if (
        typeof stk?.['CheckoutRequestID'] !== 'string' ||
        typeof stk?.['ResultCode'] !== 'number'
      ) {
        return null;
      }
      return {
        checkoutRequestId: stk['CheckoutRequestID'],
        ...(typeof stk['MerchantRequestID'] === 'string'
          ? { merchantRequestId: stk['MerchantRequestID'] }
          : {}),
        resultCode: String(stk['ResultCode']),
        resultDescription:
          typeof stk['ResultDesc'] === 'string' ? stk['ResultDesc'] : '',
      };
    }
    const checkoutRequestId = stk['CheckoutRequestID'];
    const resultCode = stk['ResultCode'];
    if (typeof checkoutRequestId !== 'string' || typeof resultCode !== 'number') {
      return null;
    }
    const values = (callbackItems as unknown[])
      .filter(isRecord)
      .reduce<Record<string, unknown>>((result, item) => {
        if (typeof item['Name'] === 'string') result[item['Name']] = item['Value'];
        return result;
      }, {});
    return {
      checkoutRequestId,
      ...(typeof stk['MerchantRequestID'] === 'string'
        ? { merchantRequestId: stk['MerchantRequestID'] }
        : {}),
      resultCode: String(resultCode),
      resultDescription:
        typeof stk['ResultDesc'] === 'string' ? stk['ResultDesc'] : '',
      ...(typeof values['MpesaReceiptNumber'] === 'string'
        ? { receiptNumber: values['MpesaReceiptNumber'] }
        : {}),
      ...(typeof values['Amount'] === 'number' ||
      typeof values['Amount'] === 'string'
        ? { amount: String(values['Amount']) }
        : {}),
      ...(typeof values['PhoneNumber'] === 'number' ||
      typeof values['PhoneNumber'] === 'string'
        ? { phoneNumber: String(values['PhoneNumber']) }
        : {}),
      ...(typeof values['TransactionDate'] === 'number'
        ? { transactionDate: String(values['TransactionDate']) }
        : {}),
    };
  }
}
