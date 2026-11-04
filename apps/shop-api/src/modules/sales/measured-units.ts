import unitCatalogue from '../../../../../packages/units/units.json';

type Unit = { symbol: string; factorToBase: number };
type Family = { base: string; units: Record<string, Unit> };
const families = unitCatalogue.families as Record<string, Family>;
const unitIndex = new Map<string, { family: string; unit: Unit }>();
for (const [family, definition] of Object.entries(families)) {
  for (const [key, unit] of Object.entries(definition.units)) {
    unitIndex.set(key, { family, unit });
  }
}

export class UnitConversionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UnitConversionError';
  }
}

/** Convert a sold quantity to a product's stored base unit in integer milli-units. */
export function toBaseQuantity(
  quantity: string | number,
  soldUnit: string,
  productUnit: string,
): number {
  const sold = unitIndex.get(soldUnit.toLowerCase());
  const product = unitIndex.get(productUnit.toLowerCase());
  if (!sold || !product) throw new UnitConversionError('Choose a supported product unit.');
  if (sold.family !== product.family) {
    throw new UnitConversionError(`Unit ${sold.unit.symbol} is incompatible with ${product.unit.symbol}.`);
  }
  const text = String(quantity).trim();
  const match = /^(\d+)(?:\.(\d+))?$/.exec(text);
  if (!match) throw new UnitConversionError('Quantity must be a positive decimal number.');
  const fraction = match[2] ?? '';
  if (fraction.length > 6) throw new UnitConversionError('Quantity precision is too fine.');
  const scale = 10 ** fraction.length;
  const unitsNumerator = Number(match[1]) * scale + Number(fraction || 0);
  const baseMilliNumerator = unitsNumerator * sold.unit.factorToBase * 1000;
  const divisor = scale * product.unit.factorToBase;
  if (baseMilliNumerator % divisor !== 0) {
    throw new UnitConversionError('Quantity is finer than 3 decimal places of the product base unit.');
  }
  const milli = baseMilliNumerator / divisor;
  if (!Number.isSafeInteger(milli) || milli <= 0) {
    throw new UnitConversionError('Quantity must convert to a positive supported amount.');
  }
  return milli;
}

export function unitSymbol(unit: string): string | undefined {
  return unitIndex.get(unit.toLowerCase())?.unit.symbol;
}
