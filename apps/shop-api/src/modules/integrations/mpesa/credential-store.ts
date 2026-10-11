import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from 'node:crypto';
import { readFileSync } from 'node:fs';
import type { MpesaCredentials } from './mpesa.contract';

const ENVELOPE_VERSION = 1;
const ALGORITHM = 'aes-256-gcm';

export interface MpesaMerchantConfiguration extends MpesaCredentials {
  accountReference: string;
}

interface EncryptedEnvelope {
  version: number;
  algorithm: string;
  iv: string;
  authTag: string;
  ciphertext: string;
}

export class MpesaConfigurationError extends Error {
  constructor(
    readonly code:
      | 'ENCRYPTION_KEY_UNAVAILABLE'
      | 'CREDENTIALS_NOT_CONFIGURED'
      | 'CREDENTIALS_INVALID',
    message: string,
  ) {
    super(message);
  }
}

function encryptionKey(): Buffer {
  let encoded = process.env.MPESA_CREDENTIALS_ENCRYPTION_KEY;
  const keyFile = process.env.MPESA_CREDENTIALS_ENCRYPTION_KEY_FILE;
  if (!encoded && keyFile) {
    try {
      encoded = readFileSync(keyFile, 'utf8').trim();
    } catch {
      throw new MpesaConfigurationError(
        'ENCRYPTION_KEY_UNAVAILABLE',
        'The server encryption key is unavailable.',
      );
    }
  }
  if (!encoded || !/^[A-Za-z0-9+/]{43}=$/.test(encoded)) {
    throw new MpesaConfigurationError(
      'ENCRYPTION_KEY_UNAVAILABLE',
      'The server encryption key is unavailable.',
    );
  }
  const key = Buffer.from(encoded, 'base64');
  if (key.length !== 32 || key.toString('base64') !== encoded) {
    throw new MpesaConfigurationError(
      'ENCRYPTION_KEY_UNAVAILABLE',
      'The server encryption key is invalid.',
    );
  }
  return key;
}

export function encryptMpesaConfiguration(
  configuration: MpesaMerchantConfiguration,
): EncryptedEnvelope {
  const iv = randomBytes(12);
  const cipher = createCipheriv(ALGORITHM, encryptionKey(), iv);
  const ciphertext = Buffer.concat([
    cipher.update(JSON.stringify(configuration), 'utf8'),
    cipher.final(),
  ]);
  return {
    version: ENVELOPE_VERSION,
    algorithm: ALGORITHM,
    iv: iv.toString('base64'),
    authTag: cipher.getAuthTag().toString('base64'),
    ciphertext: ciphertext.toString('base64'),
  };
}

export function decryptMpesaConfiguration(
  envelopeValue: unknown,
): MpesaMerchantConfiguration {
  const envelope = envelopeValue as Partial<EncryptedEnvelope> | null;
  if (
    !envelope ||
    envelope.version !== ENVELOPE_VERSION ||
    envelope.algorithm !== ALGORITHM ||
    typeof envelope.iv !== 'string' ||
    typeof envelope.authTag !== 'string' ||
    typeof envelope.ciphertext !== 'string'
  ) {
    throw new MpesaConfigurationError(
      'CREDENTIALS_INVALID',
      'The saved M-Pesa configuration is invalid.',
    );
  }
  try {
    const decipher = createDecipheriv(
      ALGORITHM,
      encryptionKey(),
      Buffer.from(envelope.iv, 'base64'),
    );
    decipher.setAuthTag(Buffer.from(envelope.authTag, 'base64'));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(envelope.ciphertext, 'base64')),
      decipher.final(),
    ]).toString('utf8');
    const configuration: unknown = JSON.parse(plaintext);
    if (
      typeof configuration !== 'object' ||
      configuration === null ||
      !('consumerKey' in configuration) ||
      typeof configuration.consumerKey !== 'string' ||
      !('consumerSecret' in configuration) ||
      typeof configuration.consumerSecret !== 'string' ||
      !('passkey' in configuration) ||
      typeof configuration.passkey !== 'string' ||
      !('shortcode' in configuration) ||
      typeof configuration.shortcode !== 'string' ||
      !('environment' in configuration) ||
      (configuration.environment !== 'sandbox' &&
        configuration.environment !== 'production') ||
      !('transactionType' in configuration) ||
      (configuration.transactionType !== 'CustomerPayBillOnline' &&
        configuration.transactionType !== 'CustomerBuyGoodsOnline') ||
      !('accountReference' in configuration) ||
      typeof configuration.accountReference !== 'string'
    ) {
      throw new Error('Invalid decrypted configuration.');
    }
    return configuration as MpesaMerchantConfiguration;
  } catch (error) {
    if (error instanceof MpesaConfigurationError) throw error;
    throw new MpesaConfigurationError(
      'CREDENTIALS_INVALID',
      'The saved M-Pesa configuration could not be decrypted.',
    );
  }
}
