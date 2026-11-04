import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PrismaClient } from '@prisma/client';

const businessId = process.env.BUSINESS_ID;
if (!businessId || !/^[0-9a-f-]{36}$/i.test(businessId)) {
  throw new Error('Set BUSINESS_ID to a single shop UUID; refusing an unscoped unit audit.');
}

async function main(): Promise<void> {
  const scriptDirectory = dirname(fileURLToPath(import.meta.url));
  const cataloguePath = resolve(scriptDirectory, '../../../packages/units/units.json');
  const catalogue = JSON.parse(await readFile(cataloguePath, 'utf8')) as {
    families: Record<string, { units: Record<string, { symbol: string; factorToBase: number }> }>;
  };
  const unitMap = new Map<string, { family: string; symbol: string }>();
  for (const [family, definition] of Object.entries(catalogue.families)) {
    for (const [id, unit] of Object.entries(definition.units)) {
      unitMap.set(id, { family, symbol: unit.symbol });
    }
  }

  const prisma = new PrismaClient();
  try {
    const units = await prisma.$queryRaw<Array<{ unit: string; products: bigint }>>`
      SELECT "unit", COUNT(*) AS products
      FROM "products"
      WHERE "businessId" = ${businessId}::uuid
      GROUP BY "unit"
      ORDER BY "unit"
    `;
    const result = units.map((row) => ({
      unit: row.unit,
      products: Number(row.products),
      catalogue: unitMap.get(row.unit) ?? null,
    }));
    const unmapped = result.filter((row) => row.catalogue == null).map((row) => row.unit);
    console.log(JSON.stringify({ businessId, units: result, unmapped }, null, 2));
    if (unmapped.length > 0) process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

void main();
