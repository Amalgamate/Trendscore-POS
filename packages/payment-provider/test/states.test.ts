import { describe, expect, it } from 'vitest';
import {
  DARajaResultCode,
  InvalidTransitionError,
  canTransition,
  describeState,
  isTerminal,
  needsReconciliation,
  stateFromResultCode,
  transition,
} from '../src/states.js';

describe('payment state machine', () => {
  it('treats TIMEOUT and UNKNOWN as non-terminal', () => {
    // These are the two states that cause real financial bugs if treated
    // as final. A timed-out M-Pesa prompt can still settle.
    expect(isTerminal('TIMEOUT')).toBe(false);
    expect(isTerminal('UNKNOWN')).toBe(false);
    expect(needsReconciliation('TIMEOUT')).toBe(true);
    expect(needsReconciliation('UNKNOWN')).toBe(true);
  });

  it('treats SUCCESS, FAILED and CANCELLED as terminal', () => {
    expect(isTerminal('SUCCESS')).toBe(true);
    expect(isTerminal('FAILED')).toBe(true);
    expect(isTerminal('CANCELLED')).toBe(true);
  });

  it('allows the happy path', () => {
    expect(transition('INITIATED', 'PROMPT_SENT')).toBe('PROMPT_SENT');
    expect(transition('PROMPT_SENT', 'WAITING')).toBe('WAITING');
    expect(transition('WAITING', 'SUCCESS')).toBe('SUCCESS');
  });

  it('allows a late success from TIMEOUT', () => {
    expect(canTransition('TIMEOUT', 'SUCCESS')).toBe(true);
    expect(transition('TIMEOUT', 'SUCCESS')).toBe('SUCCESS');
  });

  it('allows a late success from UNKNOWN', () => {
    expect(canTransition('UNKNOWN', 'SUCCESS')).toBe(true);
  });

  it('routes a settled failure back through UNKNOWN, never straight to SUCCESS', () => {
    // Auditability: the record must pass back through UNKNOWN so the
    // correction is visible, rather than silently flipping.
    expect(canTransition('FAILED', 'SUCCESS')).toBe(false);
    expect(canTransition('FAILED', 'UNKNOWN')).toBe(true);
    expect(transition('FAILED', 'UNKNOWN')).toBe('UNKNOWN');
    expect(transition('UNKNOWN', 'SUCCESS')).toBe('SUCCESS');
  });

  it('refuses to move out of a terminal success', () => {
    expect(canTransition('SUCCESS', 'FAILED')).toBe(false);
    expect(() => transition('SUCCESS', 'FAILED')).toThrow(InvalidTransitionError);
  });

  it('refuses to skip the prompt', () => {
    expect(canTransition('INITIATED', 'SUCCESS')).toBe(false);
  });

  it('maps Daraja result codes conservatively', () => {
    expect(stateFromResultCode(DARajaResultCode.SUCCESS)).toBe('SUCCESS');
    expect(stateFromResultCode(DARajaResultCode.INSUFFICIENT_FUNDS)).toBe('FAILED');
    // Everything ambiguous becomes UNKNOWN, never FAILED.
    expect(stateFromResultCode('1032')).toBe('UNKNOWN');
    expect(stateFromResultCode('2006')).toBe('UNKNOWN');
    expect(stateFromResultCode('anything-else')).toBe('UNKNOWN');
  });

  it('never tells a shop owner a raw result code', () => {
    for (const s of [
      'INITIATED', 'PROMPT_SENT', 'WAITING', 'SUCCESS',
      'FAILED', 'CANCELLED', 'TIMEOUT', 'UNKNOWN',
    ] as const) {
      const copy = describeState(s);
      expect(copy.length).toBeGreaterThan(0);
      expect(copy).not.toMatch(/\d{4}/);
    }
  });

  it('sets honest expectations on timeout rather than claiming failure', () => {
    expect(describeState('TIMEOUT')).toContain('confirming');
  });
});
