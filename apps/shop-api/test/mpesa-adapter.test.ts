import { afterEach, describe, expect, it, vi } from 'vitest';
import { DarajaMpesaAdapter } from '../src/modules/integrations/mpesa/daraja.adapter';
import {
  decryptMpesaConfiguration,
  encryptMpesaConfiguration,
  MpesaConfigurationError,
} from '../src/modules/integrations/mpesa/credential-store';

const configuration = {
  environment: 'sandbox' as const,
  shortcode: '123456',
  transactionType: 'CustomerPayBillOnline' as const,
  accountReference: 'ShopOrder',
  consumerKey: 'consumer-key-value',
  consumerSecret: 'consumer-secret-value',
  passkey: 'daraja-passkey-value',
};

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe('M-Pesa credential encryption', () => {
  it('encrypts credentials and decrypts them only with the configured server key', () => {
    vi.stubEnv(
      'MPESA_CREDENTIALS_ENCRYPTION_KEY',
      Buffer.alloc(32, 7).toString('base64'),
    );
    const encrypted = encryptMpesaConfiguration(configuration);

    expect(JSON.stringify(encrypted)).not.toContain(configuration.consumerSecret);
    expect(decryptMpesaConfiguration(encrypted)).toEqual(configuration);
  });

  it('rejects tampered credential envelopes', () => {
    vi.stubEnv(
      'MPESA_CREDENTIALS_ENCRYPTION_KEY',
      Buffer.alloc(32, 8).toString('base64'),
    );
    const encrypted = encryptMpesaConfiguration(configuration);

    expect(() =>
      decryptMpesaConfiguration({
        ...encrypted,
        ciphertext: Buffer.from('tampered').toString('base64'),
      }),
    ).toThrowError(MpesaConfigurationError);
  });

  it('refuses credential operations when the server encryption key is missing', () => {
    vi.stubEnv('MPESA_CREDENTIALS_ENCRYPTION_KEY', '');
    vi.stubEnv('MPESA_CREDENTIALS_ENCRYPTION_KEY_FILE', '');

    expect(() => encryptMpesaConfiguration(configuration)).toThrowError(
      expect.objectContaining({ code: 'ENCRYPTION_KEY_UNAVAILABLE' }),
    );
  });
});

describe('Daraja callback parsing', () => {
  const adapter = new DarajaMpesaAdapter();

  it('extracts correlated amount, phone, merchant id, and receipt metadata', () => {
    expect(
      adapter.parseCallback({
        Body: {
          stkCallback: {
            MerchantRequestID: 'merchant-request',
            CheckoutRequestID: 'checkout-request',
            ResultCode: 0,
            ResultDesc: 'Success',
            CallbackMetadata: {
              Item: [
                { Name: 'Amount', Value: 250 },
                { Name: 'MpesaReceiptNumber', Value: 'QW123ABC' },
                { Name: 'PhoneNumber', Value: 254712345678 },
              ],
            },
          },
        },
      }),
    ).toEqual({
      checkoutRequestId: 'checkout-request',
      merchantRequestId: 'merchant-request',
      resultCode: '0',
      resultDescription: 'Success',
      amount: '250',
      receiptNumber: 'QW123ABC',
      phoneNumber: '254712345678',
    });
  });

  it('parses a valid failed callback without successful-payment metadata', () => {
    expect(
      adapter.parseCallback({
        Body: {
          stkCallback: {
            CheckoutRequestID: 'checkout-request',
            ResultCode: 1032,
            ResultDesc: 'Request cancelled by user',
          },
        },
      }),
    ).toEqual({
      checkoutRequestId: 'checkout-request',
      resultCode: '1032',
      resultDescription: 'Request cancelled by user',
    });
  });

  it('ignores malformed and uncorrelated callback payloads', () => {
    expect(adapter.parseCallback(null)).toBeNull();
    expect(adapter.parseCallback({ Body: { stkCallback: {} } })).toBeNull();
  });
});
