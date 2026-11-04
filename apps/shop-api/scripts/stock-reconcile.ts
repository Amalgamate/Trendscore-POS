import { Prisma, PrismaClient } from '@prisma/client';

const businessId = process.env.BUSINESS_ID;
if (!businessId) throw new Error('BUSINESS_ID must be set; refusing an unscoped stock reconciliation.');

async function main() {
 const prisma = new PrismaClient();
 try {
  const products = await prisma.$queryRaw<Array<{
    id: string; name: string; stock: Prisma.Decimal; movementTotal: Prisma.Decimal | null;
    latestBalance: Prisma.Decimal | null; movementCount: bigint;
  }>>`
    SELECT p."id", p."name", p."stock",
      COALESCE(SUM(sm."quantity"), 0) AS "movementTotal",
      (SELECT last."balanceAfter" FROM "stock_movements" last WHERE last."productId"=p."id" ORDER BY last."createdAt" DESC, last."id" DESC LIMIT 1) AS "latestBalance",
      COUNT(sm."id") AS "movementCount"
    FROM "products" p
    LEFT JOIN "stock_movements" sm ON sm."productId"=p."id" AND sm."businessId"=p."businessId"
    WHERE p."businessId"=${businessId}::uuid
    GROUP BY p."id", p."name", p."stock"
    ORDER BY p."name", p."id"
  `;
  const mismatches = products.filter((p) => {
    const stock = new Prisma.Decimal(p.stock.toString());
    const total = new Prisma.Decimal(p.movementTotal?.toString() ?? '0');
    const latest = p.latestBalance == null ? null : new Prisma.Decimal(p.latestBalance.toString());
    return !stock.equals(total) || (latest !== null && !stock.equals(latest));
  });
  console.log(JSON.stringify({ businessId, productsChecked: products.length, mismatchCount: mismatches.length, mismatches: mismatches.map((p) => ({ id: p.id, name: p.name, stock: p.stock.toString(), movementTotal: p.movementTotal?.toString() ?? '0', latestBalance: p.latestBalance?.toString() ?? null, movementCount: p.movementCount.toString() })) }, null, 2));
  if (mismatches.length) process.exitCode = 1;
 } finally {
  await prisma.$disconnect();
 }
}
void main();
