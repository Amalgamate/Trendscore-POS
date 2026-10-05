/**
 * Seed a freshly provisioned shop instance with the minimum a shop needs
 * to trade on day one.
 *
 * Called by the provisioning engine:
 *   node dist/seed.js "James Mini Mart" james-mini-mart
 *
 * Deliberately minimal. A new owner must be able to open the POS and take
 * a sale within minutes, but must never be forced through a wizard before
 * they can trade. Everything here is either required for the app to run or
 * is a sensible starting default the owner can change later.
 *
 * Idempotent: provisioning can resume, so this may run more than once.
 */
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

/**
 * Default expense categories for a Kenyan general shop.
 *
 * These exist because the expenses screen is unusable without them, and a
 * shop owner should not have to invent a category taxonomy before their
 * first day of trading.
 */
const DEFAULT_EXPENSE_CATEGORIES: Array<{ name: string; approvalThreshold: number }> = [
  { name: 'Rent', approvalThreshold: 0 },
  { name: 'Utilities', approvalThreshold: 5000 },
  { name: 'Salaries', approvalThreshold: 0 },
  { name: 'Transport', approvalThreshold: 2000 },
  { name: 'Repairs & Maintenance', approvalThreshold: 5000 },
  { name: 'Marketing', approvalThreshold: 10000 },
  { name: 'Packaging', approvalThreshold: 5000 },
  { name: 'Bank Charges', approvalThreshold: 0 },
  { name: 'Other', approvalThreshold: 0 },
];

/**
 * Product categories a general shop almost always needs on the till grid.
 * Empty, so they cost the owner nothing until they use them.
 */
const DEFAULT_PRODUCT_CATEGORIES = [
  'Food',
  'Drinks',
  'Household',
  'Personal Care',
  'Bakery',
  'Frozen',
];

async function main(): Promise<void> {
  const [businessName, slug] = process.argv.slice(2);

  if (!businessName || !slug) {
    throw new Error('Usage: seed.js <businessName> <slug>');
  }

  const business = await prisma.business.upsert({
    where: { slug },
    update: { name: businessName },
    create: {
      name: businessName,
      slug,
      // Kenyan VAT. Stored as a decimal rate, never a float.
      vatRate: 0.16,
      currency: 'KES',
    },
  });

  // Upsert per row so a re-run adds any new default without duplicating
  // categories the owner has since renamed.
  for (const name of DEFAULT_PRODUCT_CATEGORIES) {
    await prisma.category.upsert({
      where: { businessId_name: { businessId: business.id, name } },
      update: {},
      create: { businessId: business.id, name, sortOrder: 0 },
    });
  }

  for (const category of DEFAULT_EXPENSE_CATEGORIES) {
    await prisma.expenseCategory.upsert({
      where: { businessId_name: { businessId: business.id, name: category.name } },
      update: { approvalThreshold: category.approvalThreshold },
      create: { businessId: business.id, ...category },
    });
  }

  console.log(
    JSON.stringify({
      ok: true,
      businessId: business.id,
      slug: business.slug,
      productCategories: DEFAULT_PRODUCT_CATEGORIES.length,
      expenseCategories: DEFAULT_EXPENSE_CATEGORIES.length,
    }),
  );
}

main()
  .catch((error: unknown) => {
    console.error(
      JSON.stringify({
        ok: false,
        error: error instanceof Error ? error.message : 'unknown error',
      }),
    );
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
