import { describe, expect, it } from 'vitest';
import { toBaseQuantity, UnitConversionError } from '../src/modules/sales/measured-units';
import { toCents } from '../src/modules/sales/pricing';

describe('measured unit conversion', () => {
  it('converts ml to a litre product base without floating point drift', () => {
    expect(toBaseQuantity(250, 'ml', 'l')).toBe(250);
    expect(toBaseQuantity(1000, 'ml', 'l')).toBe(1000);
    expect(20_000 - toBaseQuantity(250, 'ml', 'l')).toBe(19_750);
    expect(toBaseQuantity('0.1', 'l', 'l') + toBaseQuantity('0.2', 'l', 'l')).toBe(300);
  });

  it('rejects cross-family units and quantities finer than a base milli-unit', () => {
    expect(() => toBaseQuantity(1, 'kg', 'l')).toThrow(UnitConversionError);
    expect(() => toBaseQuantity(0.0001, 'l', 'l')).toThrow(/finer than 3 decimal places/);
  });

  it('prices measured quantities per base unit with half-up cent rounding', () => {
    const lineTotal = (price: string, quantityMilli: number) =>
      Math.floor((toCents(price) * quantityMilli + 500) / 1000);
    expect(lineTotal('300.00', toBaseQuantity(250, 'ml', 'l'))).toBe(7500);
    expect(lineTotal('285.00', toBaseQuantity(100, 'ml', 'l'))).toBe(2850);
    expect(lineTotal('1.01', 500)).toBe(51);
  });
});
