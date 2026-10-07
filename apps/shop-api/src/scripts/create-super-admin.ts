/**
 * Ensure the platform administrator exists in this shop database.
 * The initial PIN is hashed here and marked for mandatory replacement before
 * any authenticated shop API route is usable. Re-runs never reset credentials.
 */
import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';
import { readFileSync } from 'node:fs';

const prisma = new PrismaClient();

function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, '');
  if (digits.startsWith('254') && digits.length === 12) return digits;
  if (digits.startsWith('0') && digits.length === 10) return `254${digits.slice(1)}`;
  if (digits.startsWith('7') && digits.length === 9) return `254${digits}`;
  throw new Error('Enter a valid Kenyan phone number.');
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  let rawPhone: string | undefined;
  let pin: string | undefined;
  if (args.length === 1) {
    const credentials = JSON.parse(readFileSync(args[0]!, 'utf8')) as { phone?: unknown; pin?: unknown };
    rawPhone = typeof credentials.phone === 'string' ? credentials.phone : undefined;
    pin = typeof credentials.pin === 'string' ? credentials.pin : undefined;
  } else {
    [rawPhone, pin] = args;
  }
  const initialPin = pin ?? '';
  if (!rawPhone || !/^\d{4,6}$/.test(initialPin)) {
    throw new Error('Usage: create-super-admin.js <phone> <4-to-6-digit-initial-pin>');
  }

  const phone = normalizePhone(rawPhone);
  const existing = await prisma.user.findUnique({ where: { phone } });
  if (existing?.isPlatformSuperAdmin) {
    await prisma.user.update({
      where: { id: existing.id },
      data: { fullName: 'Retail OS Super Admin', role: 'OWNER', active: true },
    });
    console.log(JSON.stringify({ ok: true, created: false, role: 'OWNER' }));
    return;
  }

  const pinHash = await argon2.hash(initialPin, {
    type: argon2.argon2id,
    memoryCost: 19_456,
    timeCost: 2,
    parallelism: 1,
  });
  await prisma.user.upsert({
    where: { phone },
    update: {
      fullName: 'Retail OS Super Admin',
      pinHash,
      role: 'OWNER',
      active: true,
      mustChangePin: true,
      isPlatformSuperAdmin: true,
    },
    create: {
      fullName: 'Retail OS Super Admin',
      phone,
      pinHash,
      role: 'OWNER',
      active: true,
      mustChangePin: true,
      isPlatformSuperAdmin: true,
    },
  });
  console.log(JSON.stringify({ ok: true, created: true, role: 'OWNER' }));
}

main()
  .catch((error: unknown) => {
    console.error(JSON.stringify({
      ok: false,
      error: error instanceof Error ? error.message : 'unknown error',
    }));
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
