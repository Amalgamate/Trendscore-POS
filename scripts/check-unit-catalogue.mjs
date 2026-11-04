import { readFile } from 'node:fs/promises';

const json = JSON.parse(
  await readFile(new URL('../packages/units/units.json', import.meta.url), 'utf8'),
);
const dart = await readFile(
  new URL('../apps/shop_pos/lib/units.dart', import.meta.url),
  'utf8',
);
const cart = await readFile(
  new URL('../apps/shop_pos/lib/cart.dart', import.meta.url),
  'utf8',
);

function dartMap(name, typePattern, parseValue) {
  const declaration = new RegExp(
    `static const ${name} = ${typePattern}\\s*\\{([\\s\\S]*?)\\};`,
  );
  const body = dart.match(declaration)?.[1];
  if (!body) throw new Error(`Could not read ProductUnitCatalogue.${name}`);
  return Object.fromEntries(
    [...body.matchAll(/'([^']+)'\s*:\s*([^,]+),/g)].map(([, key, value]) => [
      key,
      parseValue(value.trim()),
    ]),
  );
}

const expectedFamilies = Object.fromEntries(
  Object.entries(json.families).map(([family, definition]) => [
    family,
    Object.keys(definition.units).sort(),
  ]),
);
const expectedFactors = Object.fromEntries(
  Object.values(json.families).flatMap((definition) =>
    Object.entries(definition.units).map(([unit, entry]) => [
      unit,
      entry.factorToBase,
    ]),
  ),
);
const expectedSymbols = Object.fromEntries(
  Object.values(json.families).flatMap((definition) =>
    Object.entries(definition.units).map(([unit, entry]) => [unit, entry.symbol]),
  ),
);

const familiesBody = dart.match(
  /static const families = <String, List<String>>\s*\{([\s\S]*?)\};/,
)?.[1];
if (!familiesBody) throw new Error('Could not read ProductUnitCatalogue.families');
const actualFamilies = Object.fromEntries(
  [...familiesBody.matchAll(/'([^']+)'\s*:\s*\[([^\]]*)\]/g)].map(
    ([, family, body]) => [
      family,
      [...body.matchAll(/'([^']+)'/g)].map((match) => match[1]).sort(),
    ],
  ),
);
const actualFactors = dartMap('factorsToBase', '<String, int>', Number);
const actualSymbols = dartMap(
  'symbols',
  '<String, String>',
  (value) => value.replace(/^'|'$/g, ''),
);

function sorted(value) {
  return Object.fromEntries(
    Object.entries(value).sort(([left], [right]) => left.localeCompare(right)),
  );
}

for (const [name, expected, actual] of [
  ['families', expectedFamilies, actualFamilies],
  ['factorsToBase', expectedFactors, actualFactors],
  ['symbols', expectedSymbols, actualSymbols],
]) {
  if (JSON.stringify(sorted(expected)) !== JSON.stringify(sorted(actual))) {
    throw new Error(
      `Unit catalogue drift in ${name}: shared JSON=${JSON.stringify(sorted(expected))}, Flutter=${JSON.stringify(sorted(actual))}`,
    );
  }
}

if (!cart.includes("import 'units.dart';") ||
    !cart.includes("export 'units.dart' show ProductUnitCatalogue;")) {
  throw new Error('Cart must use and export the shared Flutter unit catalogue.');
}

console.log('Unit catalogue matches shared JSON and is shared by Flutter cart.');
