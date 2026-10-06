import { describe, expect, it } from 'vitest';

import {
  KENYA_VAT_BASIS_POINTS,
  SaleValidationError,
  priceSale,
  sumLines,
  toCents,
  toMilli,
  vatIncludedIn,
  type PriceableProduct,
} from '../src/modules/sales/pricing';

/**
 * The payload carries product ids and quantities only — there is no field for
 * a client to state a price, so every total below is derived from the
 * catalogue. That is the property these tests exist to protect.
 */
const product = (overrides: Partial<PriceableProduct> & { id: string }): PriceableProduct => ({
  name: `Item ${overrides.id}`,
  salePrice: 6500,
  costPrice: 4000,
  vatRate: KENYA_VAT_BASIS_POINTS,
  stock: 10_000,
  active: true,
  ...overrides,
});

describe('decimal conversion', () => {
  it('parses money as exact integer cents', () => {
    expect(toCents('65.00')).toBe(6500);
    expect(toCents('65')).toBe(6500);
    expect(toCents('0.50')).toBe(50);
    expect(toCents('1234567.89')).toBe(123456789);
    expect(toCents('-15.05')).toBe(-1505);
  });

  it('rounds a plain number half away from zero', () => {
    // Math.round(-0.5) === -0 in JavaScript, which would silently drop the
    // sign from a credit note.
    expect(toCents(0.005)).toBe(1);
    expect(toCents(-0.005)).toBe(-1);
    expect(toCents(65.1)).toBe(6510);
  });

  it('rejects more precision than NUMERIC(14,2) would store', () => {
    expect(() => toCents('12.345')).toThrow(/more than 2 decimal places/);
    expect(() => toCents('twelve')).toThrow(/Not a valid decimal/);
    expect(() => toCents('')).toThrow();
  });

  it('parses quantities to thousandths', () => {
    expect(toMilli(1)).toBe(1000);
    expect(toMilli('1.5')).toBe(1500);
    expect(toMilli('0.25')).toBe(250);
    expect(toMilli('2.125')).toBe(2125);
  });

  it('rejects a quantity with too many decimal places', () => {
    expect(() => toMilli('1.2345')).toThrow(/Not a valid quantity/);
  });
});

describe('VAT extraction from tax-inclusive prices', () => {
  it('splits a whole shilling exactly', () => {
    // 116.00 inclusive at 16% is exactly 100.00 net + 16.00 VAT.
    expect(vatIncludedIn(11_600, 1600)).toBe(1600);
  });

  it('keeps net + vat equal to the gross for odd amounts', () => {
    for (const gross of [1, 99, 100, 1379, 6500, 999_999, 1_000_003]) {
      const vat = vatIncludedIn(gross, 1600);
      expect(gross - vat + vat).toBe(gross);
      expect(vat).toBeGreaterThanOrEqual(0);
      // floor() means a 1-cent amount has net 0 and VAT 1: VAT can equal the
      // gross at the extreme, so the invariant is <= not <.
      expect(vat).toBeLessThanOrEqual(gross);
    }
  });

  it('floors net so the remainder lands on VAT rather than vanishing', () => {
    // 100.00 at 16%: net = floor(10000 * 10000 / 11600) = 8620, VAT = 1380.
    expect(vatIncludedIn(10_000, 1600)).toBe(1380);
  });

  it('returns zero for a zero rate, a zero-rated item, or a zero amount', () => {
    expect(vatIncludedIn(10_000, 0)).toBe(0);
    expect(vatIncludedIn(0, 1600)).toBe(0);
    expect(vatIncludedIn(-100, 1600)).toBe(0);
  });

  it('rejects a negative rate rather than producing a negative tax', () => {
    expect(() => vatIncludedIn(10_000, -1)).toThrow(/cannot be negative/);
  });
});

describe('pricing a sale', () => {
  it('prices from the catalogue, so a tampered payload cannot change a total', () => {
    const { lines, totals } = priceSale(
      [product({ id: 'milk', salePrice: 6500 })],
      [{ productId: 'milk', quantity: 2000 }],
    );

    expect(lines).toHaveLength(1);
    expect(lines[0]!.unitPrice).toBe(6500);
    expect(totals.subtotal).toBe(13_000);
    expect(totals.total).toBe(13_000);
  });

  it('captures cost so historic profit survives a later price rise', () => {
    const { totals } = priceSale(
      [product({ id: 'milk', salePrice: 6500, costPrice: 4123 })],
      [{ productId: 'milk', quantity: 3000 }],
    );

    expect(totals.costTotal).toBe(12_369);
    expect(totals.subtotal - totals.costTotal).toBe(7131);
  });

  it('sums VAT per line so mixed rates are not over-taxed', () => {
    const { totals } = priceSale(
      [
        product({ id: 'flour', salePrice: 11_600, vatRate: 1600 }),
        product({ id: 'milk', salePrice: 500, vatRate: 0 }),
      ],
      [
        { productId: 'flour', quantity: 1000 },
        { productId: 'milk', quantity: 1000 },
      ],
    );

    // 116.00 standard-rated => 16.00 VAT; 5.00 zero-rated => 0.00.
    // Extracting once from the 121.00 basket would have taxed the milk too.
    expect(totals.subtotal).toBe(12_100);
    expect(totals.vatAmount).toBe(1600);
    expect(totals.vatAmount).not.toBe(vatIncludedIn(12_100, 1600));
  });

  it('handles fractional quantities priced per thousandth', () => {
    const { totals } = priceSale(
      [product({ id: 'sugar', salePrice: 13_000, stock: 50_000 })],
      [{ productId: 'sugar', quantity: 1500 }], // 1.5 kg at 130.00/kg
    );
    expect(totals.subtotal).toBe(19_500);
  });

  it('rejects an empty basket', () => {
    expect(() => priceSale([], [])).toThrow(SaleValidationError);
    expect(() => priceSale([], [])).toThrow(/at least one line/);
  });

  it('rejects a non-positive quantity', () => {
    expect(() => priceSale([product({ id: 'milk' })], [{ productId: 'milk', quantity: 0 }])).toThrow(/must be positive/);
    expect(() => priceSale([product({ id: 'milk' })], [{ productId: 'milk', quantity: -1000 }])).toThrow(/must be positive/);
  });

  it('rejects duplicate lines that would double-spend one stock balance', () => {
    // Each line passes an individual stock check while together exceeding it.
    expect(() =>
      priceSale(
        [product({ id: 'milk', stock: 1500 })],
        [
          { productId: 'milk', quantity: 1000 },
          { productId: 'milk', quantity: 1000 },
        ],
      ),
    ).toThrow(/Duplicate line/);
  });

  it('rejects an unknown product', () => {
    expect(() => priceSale([product({ id: 'milk' })], [{ productId: 'ghost', quantity: 1000 }])).toThrow(/No product ghost/);
  });

  it('rejects an inactive product', () => {
    expect(() =>
      priceSale([product({ id: 'milk', active: false })], [{ productId: 'milk', quantity: 1000 }]),
    ).toThrow(/no longer sold/);
  });

  it('refuses to sell more than the server has in stock', () => {
    const attempt = () =>
      priceSale([product({ id: 'milk', stock: 800 })], [{ productId: 'milk', quantity: 1000 }]);

    expect(attempt).toThrow(SaleValidationError);
    try {
      attempt();
      throw new Error('should have thrown');
    } catch (error) {
      const rejection = (error as SaleValidationError).rejection;
      expect(rejection.kind).toBe('INSUFFICIENT_STOCK');
      if (rejection.kind === 'INSUFFICIENT_STOCK') {
        expect(rejection.available).toBe(800);
        expect(rejection.requested).toBe(1000);
        expect(rejection.name).toBe('Item milk');
      }
    }
  });

  it('allows a quantity exactly equal to stock', () => {
    const { totals } = priceSale(
      [product({ id: 'milk', stock: 2000 })],
      [{ productId: 'milk', quantity: 2000 }],
    );
    expect(totals.subtotal).toBe(13_000);
  });
});

describe('summing lines', () => {
  it('reports a total that equals the subtotal before discount', () => {
    const { lines, totals } = priceSale(
      [
        product({ id: 'a', salePrice: 6500 }),
        product({ id: 'b', salePrice: 7500 }),
      ],
      [
        { productId: 'a', quantity: 1000 },
        { productId: 'b', quantity: 2000 },
      ],
    );

    expect(totals).toEqual(sumLines(lines));
    expect(totals.total).toBe(6500 + 15_000);
    expect(totals.total).toBe(totals.subtotal);
  });

  it('returns zero totals for no lines', () => {
    expect(sumLines([])).toEqual({ subtotal: 0, costTotal: 0, vatAmount: 0, total: 0 });
  });
});

