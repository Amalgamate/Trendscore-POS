/**
 * Sale pricing — the server's own arithmetic.
 *
 * This module deliberately trusts **nothing the client sends about money**.
 * The POS posts product ids and quantities; prices, cost, and VAT are read
 * from the database here. A till that accepts a price from the wire is a till
 * that can be told a 2,000 KES phone costs 1.00 — and the ledger would record
 * it faithfully, because the ledger is append-only and cannot be corrected,
 * only reversed. So: the client proposes, the server disposes.
 *
 * Every amount is an integer number of minor units (cents). The schema
 * enforces NUMERIC(14,2) and migration `0001_immutable_ledgers` fails the
 * build if any financial column drifts to a float; this keeps the application
 * side of that boundary honest too. Binary floats cannot represent 0.10, and
 * a till that is off by a cent at close of day is a till that cannot be
 * reconciled.
 *
 * No imports from Prisma or Express: this is pure arithmetic, so it is tested
 * directly rather than through a database or an HTTP harness.
 */

/** Kenyan standard rate, in basis points. Matches `Business.vatRate` default. */
export const KENYA_VAT_BASIS_POINTS = 1600;

/** An amount in cents. */
export type Cents = number;

/** A quantity in thousandths, matching `products.stock DECIMAL(14,3)`. */
export type Milli = number;

export interface PriceableProduct {
  id: string;
  name: string;
  /** In cents. */
  salePrice: Cents;
  /** In cents, captured at sale time for historic profit. */
  costPrice: Cents;
  /** Basis points, e.g. 1600 for 16%. */
  vatRate: number;
  /** In thousandths of a unit. */
  stock: Milli;
  active: boolean;
}

export interface RequestedLine {
  productId: string;
  quantity: Milli;
}

export interface PricedLine {
  productId: string;
  name: string;
  quantity: Milli;
  unitPrice: Cents;
  unitCost: Cents;
  vatRate: number;
  lineTotal: Cents;
  lineCost: Cents;
}

export interface SaleTotals {
  subtotal: Cents;
  costTotal: Cents;
  /** VAT already contained in `subtotal` (shelf prices are tax-inclusive). */
  vatAmount: Cents;
  total: Cents;
}

/** Why a sale was rejected. Machine-readable so the POS can react. */
export type SaleRejection =
  | { kind: 'PRODUCT_NOT_FOUND'; productId: string }
  | { kind: 'PRODUCT_INACTIVE'; productId: string; name: string }
  | { kind: 'INSUFFICIENT_STOCK'; productId: string; name: string; available: Milli; requested: Milli }
  | { kind: 'QUANTITY_NOT_POSITIVE'; productId: string; requested: Milli }
  | { kind: 'DUPLICATE_PRODUCT'; productId: string }
  | { kind: 'EMPTY_SALE' };


/** Rounds half away from zero. `Math.round` rounds -0.5 to -0, which is wrong for money. */
function roundHalfAway(value: number): number {
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/**
 * Converts a Prisma/Postgres decimal, a string, or a number into integer cents.
 *
 * Goes through the decimal *text* when given one: `parseFloat('65.10')` cannot
 * represent 65.10 exactly, and that error is inherited for the life of the
 * row. Anything with more than two decimal places is a schema violation and
 * throws rather than silently rounding someone's money.
 */
export function toCents(value: string | number): Cents {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error(`Not a finite amount: ${value}`);
    return roundHalfAway(value * 100);
  }
  const trimmed = value.trim();
  const match = /^(-?)(\d+)(?:\.(\d+))?$/.exec(trimmed);
  if (!match) throw new Error(`Not a valid decimal amount: "${value}"`);
  const sign = match[1] === '-' ? -1 : 1;
  const whole = Number(match[2]);
  const fraction = match[3] ?? '';
  if (fraction.length > 2) {
    // NUMERIC(14,2) would reject this too. Refusing here means the caller
    // finds out from a test or a 500, not from a quietly truncated receipt.
    throw new Error(`Amount "${value}" has more than 2 decimal places`);
  }
  return sign * (whole * 100 + Number(fraction.padEnd(2, '0') || '0'));
}

/** Converts a decimal-as-text quantity (e.g. "1.500" kg) into thousandths. */
export function toMilli(value: string | number): Milli {
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) throw new Error(`Not a finite quantity: ${value}`);
    return roundHalfAway(value * 1000);
  }
  const trimmed = value.trim();
  const match = /^(-?)(\d+)(?:\.(\d{1,3}))?$/.exec(trimmed);
  if (!match) throw new Error(`Not a valid quantity: "${value}"`);
  const sign = match[1] === '-' ? -1 : 1;
  const fraction = (match[3] ?? '').padEnd(3, '0');
  return sign * (Number(match[2]) * 1000 + Number(fraction));
}

/**
 * Extracts the VAT already contained in a tax-inclusive amount.
 *
 * Kenyan retail displays VAT-inclusive shelf prices, so the customer has
 * already paid the tax inside the total. Reporting it therefore means dividing
 * out — the inverse of the usual "add tax on top":
 *
 *     net = gross * 10000 / (10000 + rate)      // floored
 *     vat = gross - net
 *
 * Flooring `net` puts the remainder on the VAT side, so `net + vat` re-adds to
 * the gross exactly. No cent is invented or lost, and the invariant holds for
 * every rate and every odd gross.
 */
export function vatIncludedIn(grossCents: Cents, rateBasisPoints: number): Cents {
  if (rateBasisPoints < 0) throw new Error(`VAT rate cannot be negative: ${rateBasisPoints}`);
  if (grossCents <= 0) return 0;
  const divisor = 10000 + rateBasisPoints;
  const net = Math.floor((grossCents * 10000) / divisor);
  return grossCents - net;
}

export class SaleValidationError extends Error {
  constructor(public readonly rejection: SaleRejection, message: string) {
    super(message);
    this.name = 'SaleValidationError';
  }
}

/**
 * Prices a proposed sale from database truth.
 *
 * The client sends ids and quantities only. Prices, cost and stock all come
 * from [products], so a tampered payload can change *what* is sold but never
 * *at what price*. Each rejection carries enough structure for the POS to tell
 * the cashier which line is the problem — a guard the cashier cannot see is
 * indistinguishable from a broken till.
 *
 * Throws [SaleValidationError] rather than returning a partial price: a sale
 * priced from an incomplete picture is worse than no sale.
 */
export function priceSale(
  products: readonly PriceableProduct[],
  requested: readonly RequestedLine[],
): { lines: PricedLine[]; totals: SaleTotals } {
  if (requested.length === 0) throw new SaleValidationError({ kind: 'EMPTY_SALE' }, 'A sale needs at least one line');

  const catalogue = new Map(products.map((product) => [product.id, product]));
  const seen = new Set<string>();
  const lines: PricedLine[] = [];

  for (const line of requested) {
    if (line.quantity <= 0) {
      throw new SaleValidationError(
        { kind: 'QUANTITY_NOT_POSITIVE', productId: line.productId, requested: line.quantity },
        `Quantity for ${line.productId} must be positive, got ${line.quantity}`,
      );
    }
    if (seen.has(line.productId)) {
      // Duplicate ids would otherwise price twice against one stock balance
      // and let the second line oversell the first.
      throw new SaleValidationError({ kind: 'DUPLICATE_PRODUCT', productId: line.productId }, `Duplicate line for ${line.productId}`);
    }
    seen.add(line.productId);

    const product = catalogue.get(line.productId);
    if (!product) {
      throw new SaleValidationError({ kind: 'PRODUCT_NOT_FOUND', productId: line.productId }, `No product ${line.productId}`);
    }
    if (!product.active) {
      throw new SaleValidationError({ kind: 'PRODUCT_INACTIVE', productId: line.productId, name: product.name }, `${product.name} is no longer sold`);
    }
    if (line.quantity > product.stock) {
      // Stock is checked against the *server's* balance, not the till's
      // cached copy: two tills can hold the same last unit of stock.
      throw new SaleValidationError(
        { kind: 'INSUFFICIENT_STOCK', productId: product.id, name: product.name, available: product.stock, requested: line.quantity },
        `Only ${product.stock / 1000} ${product.name} in stock, ${line.quantity / 1000} requested`,
      );
    }

    const lineTotal = roundHalfAway((product.salePrice * line.quantity) / 1000);
    const lineCost = roundHalfAway((product.costPrice * line.quantity) / 1000);
    lines.push({
      productId: product.id,
      name: product.name,
      quantity: line.quantity,
      unitPrice: product.salePrice,
      unitCost: product.costPrice,
      vatRate: product.vatRate,
      lineTotal,
      lineCost,
    });
  }

  return { lines, totals: sumLines(lines) };
}

/** Totals a priced basket. VAT is summed per line, never recomputed on the sum. */
export function sumLines(lines: readonly PricedLine[]): SaleTotals {
  let subtotal = 0;
  let costTotal = 0;
  let vatAmount = 0;

  for (const line of lines) {
    subtotal += line.lineTotal;
    costTotal += line.lineCost;
    // Each line may carry its own rate — zero-rated staples sit alongside
    // standard-rated goods in the same basket — so VAT is extracted per line
    // and then added. Extracting once from the basket total would apply the
    // standard rate to items that are not standard-rated.
    vatAmount += vatIncludedIn(line.lineTotal, line.vatRate);
  }

  return { subtotal, costTotal, vatAmount, total: subtotal };
}

