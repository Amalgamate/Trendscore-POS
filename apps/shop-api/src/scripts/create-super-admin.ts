/**
 * Ensure the platform administrator exists in this shop database.
 *
 * New account: created with the supplied initial PIN and mustChangePin = true,
 * so the admin must set their own PIN at first login.
 * Existing account: the PIN and mustChangePin are left untouched, so re-running
 * this script never forces a PIN change or resets a PIN the admin already chose.
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
  const pinHash = await argon2.hash(initialPin, {
    type: argon2.argon2id,
    memoryCost: 19_456,
    timeCost: 2,
    parallelism: 1,
  });

  const existing = await prisma.user.findUnique({ where: { phone } });
  if (existing?.isPlatformSuperAdmin) {
    // Existing admin: never touch pinHash or mustChangePin.
    await prisma.user.update({
      where: { id: existing.id },
      data: { fullName: 'Retail OS Super Admin', role: 'SUPER_ADMIN', active: true },
    });
    console.log(JSON.stringify({ ok: true, created: false, role: 'SUPER_ADMIN' }));
    return;
  }

  await prisma.user.upsert({
    where: { phone },
    update: {
      // Existing user being promoted: keep their PIN and do not force a change.
      fullName: 'Retail OS Super Admin',
      role: 'SUPER_ADMIN',
      active: true,
      isPlatformSuperAdmin: true,
    },
    create: {
      fullName: 'Retail OS Super Admin',
      phone,
      pinHash,
      role: 'SUPER_ADMIN',
      active: true,
      mustChangePin: true,
      isPlatformSuperAdmin: true,
    },
  });
  console.log(JSON.stringify({ ok: true, created: true, role: 'SUPER_ADMIN' }));
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