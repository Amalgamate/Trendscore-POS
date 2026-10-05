import { describe, expect, it } from 'vitest';
import { FakeMpesaProvider } from '../src/providers/fake-mpesa.js';
import { CashProvider, CreditProvider } from '../src/providers/internal.js';
import { PaymentRegistry } from '../src/registry.js';
import {
  RECONCILE_WINDOW_HOURS,
  CONTRADICTION_THRESHOLD,
  decideReconcile,
  nextPollDelayMs,
  shouldKeepPolling,
} from '../src/reconcile.js';
import { PaymentError, isValidMsisdn, normaliseMsisdn } from '../src/types.js';

const req = (over: Partial<Parameters<FakeMpesaProvider['processPayment']>[0]> = {}) => ({
  idempotencyKey: 'key-001',
  amount: '899.00',
  currency: 'KES' as const,
  msisdn: '254700000001',
  description: 'Test',
  reference: 'SALE-1',
  ...over,
});

describe('msisdn normalisation', () => {
  it('normalises local, national and international forms', () => {
    expect(normaliseMsisdn('0712345678')).toBe('254712345678');
    expect(normaliseMsisdn('+254 712 345 678')).toBe('254712345678');
    expect(normaliseMsisdn('254712345678')).toBe('254712345678');
    expect(normaliseMsisdn('712345678')).toBe('254712345678');
  });

  it('rejects garbage', () => {
    expect(isValidMsisdn('12345')).toBe(false);
    expect(() => normaliseMsisdn('abc')).toThrow(PaymentError);
  });
});

describe('FakeMpesaProvider', () => {
  it('starts every payment at PROMPT_SENT, never SUCCESS', () => {
    // The bug this prevents: assuming the tap succeeded because we called it.
    const p = new FakeMpesaProvider();
    return expect(p.processPayment(req())).resolves.toMatchObject({ state: 'PROMPT_SENT' });
  });

  it('is replay-safe on the same idempotency key', () => {
    const p = new FakeMpesaProvider();
    const first = p.processPayment(req());
    return Promise.all([first, p.processPayment(req())]).then(([a, b]) => {
      expect(a.providerReference).toBe(b.providerReference);
      expect(a.initiatedAt.getTime()).toBe(b.initiatedAt.getTime());
    });
  });

  it('caps amount at the Daraja STK limit of 70,000', () => {
    const p = new FakeMpesaProvider();
    expect(p.supportsAmount('70000.00')).toBe(true);
    expect(p.supportsAmount('70000.01')).toBe(false);
    expect(p.supportsAmount('0')).toBe(false);
    expect(p.supportsAmount('-5')).toBe(false);
  });

  it('maps msisdn suffixes to deterministic scenarios', () => {
    const p = new FakeMpesaProvider();
    const expectScenario = async (msisdn: string, key: string, want: string) => {
      const r = await p.processPayment(req({ idempotencyKey: key, msisdn }));
      expect(p.scenarioOf(r.idempotencyKey)).toBe(want);
    };
    return Promise.all([
      expectScenario('254700000001', 's1', 'SUCCESS'),
      expectScenario('254700000002', 's2', 'FAILED'),
      expectScenario('254700000003', 's3', 'LATE_SETTLE'),
      expectScenario('254700000004', 's4', 'UNKNOWN'),
      expectScenario('254700000005', 's5', 'CANCELLED'),
    ]);
  });

  it('resolves a late settlement after a timeout', () => {
    const p = new FakeMpesaProvider();
    return p
      .processPayment(req({ idempotencyKey: 'late-1', msisdn: '254700000003' }))
      .then((r) => p.resolve(r.idempotencyKey, 'TIMEOUT'))
      .then((timedOut) => {
        expect(timedOut.state).toBe('TIMEOUT');
        // Money arrives later — must not be lost.
        const settled = p.resolve(timedOut.idempotencyKey, 'SUCCESS');
        expect(settled.state).toBe('SUCCESS');
        expect(settled.receiptNumber).toBeTruthy();
      });
  });
});

describe('reconciliation decisions', () => {
  const rec = (state: string) => ({
    provider: 'MPESA' as const,
    state: state as never,
    idempotencyKey: 'k',
    amount: '100.00',
    msisdn: '254700000001',
    initiatedAt: new Date(),
  });

  it('applies a late success when nothing was settled', () => {
    const d = decideReconcile(rec('TIMEOUT'), rec('SUCCESS'));
    expect(d.action).toBe('apply_success');
  });

  it('writes a reversal when success arrives after we settled a failure', () => {
    const d = decideReconcile(rec('FAILED'), rec('SUCCESS'));
    expect(d.action).toBe('write_reversal');
  });

  it('re-queries before reversing a recorded success', () => {
    // A single contradicting read is far more likely a glitch than a
    // genuine clawed-back settlement. Do not touch the ledger yet.
    expect(decideReconcile(rec('SUCCESS'), rec('FAILED')).action).toBe('keep_polling');
    expect(decideReconcile(rec('SUCCESS'), rec('UNKNOWN')).action).toBe('keep_polling');
  });

  it('escalates to a reversal once the contradiction persists', () => {
    expect(decideReconcile(rec('SUCCESS'), rec('FAILED'), 3).action).toBe('write_reversal');
  });

  it('does nothing when the states already agree', () => {
    expect(decideReconcile(rec('SUCCESS'), rec('SUCCESS')).action).toBe('none');
    expect(decideReconcile(rec('UNKNOWN'), rec('UNKNOWN')).action).toBe('none');
  });

  it('applies a definitive failure on an in-flight payment', () => {
    expect(decideReconcile(rec('WAITING'), rec('FAILED')).action).toBe('apply_failure');
    expect(decideReconcile(rec('TIMEOUT'), rec('CANCELLED')).action).toBe('apply_failure');
  });

  it('stops polling terminal payments but keeps unknown ones within the window', () => {
    expect(shouldKeepPolling('SUCCESS', 1000)).toBe(false);
    expect(shouldKeepPolling('UNKNOWN', 1000)).toBe(true);
    expect(shouldKeepPolling('TIMEOUT', 1000)).toBe(true);
    // Past the 24h window we stop even for UNKNOWN.
    expect(shouldKeepPolling('UNKNOWN', 25 * 60 * 60 * 1000)).toBe(false);
    expect(RECONCILE_WINDOW_HOURS).toBe(24);
  });

  it('tolerates a few contradictions before escalating', () => {
    expect(CONTRADICTION_THRESHOLD).toBeGreaterThan(1);
  });

  it('backs off so a dead payment does not burn the API quota', () => {
    const delays = [0, 1, 2, 3, 8].map(nextPollDelayMs);
    for (let i = 1; i < delays.length; i++) {
      expect(delays[i]!).toBeGreaterThanOrEqual(delays[i - 1]!);
    }
    expect(nextPollDelayMs(99)).toBe(60 * 60 * 1000);
  });
});

describe('registry', () => {
  it('keeps the POS ignorant of which provider handles a method', async () => {
    const reg = new PaymentRegistry()
      .register(new CashProvider())
      .register(new CreditProvider())
      .register(new FakeMpesaProvider());

    expect(reg.enabledMethods().sort()).toEqual(['CASH', 'CREDIT', 'MPESA']);

    // One call path for every method.
    await expect(reg.process('CASH', req({ idempotencyKey: 'c1' }))).resolves.toMatchObject({
      state: 'SUCCESS',
      provider: 'CASH',
    });
    await expect(reg.process('CREDIT', req({ idempotencyKey: 'r1' }))).resolves.toMatchObject({
      state: 'SUCCESS',
      provider: 'CREDIT',
    });
    await expect(reg.process('MPESA', req({ idempotencyKey: 'm1' }))).resolves.toMatchObject({
      state: 'PROMPT_SENT',
    });
  });

  it('throws a clear error for an unregistered method', () => {
    const reg = new PaymentRegistry();
    expect(() => reg.get('MPESA')).toThrow(PaymentError);
  });

  it('rejects non-positive amounts on internal providers', async () => {
    await expect(
      new CashProvider().processPayment(req({ amount: '0' })),
    ).rejects.toThrow(PaymentError);
  });
});
