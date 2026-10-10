/**
 * Ensure the platform administrator exists in this shop database.
 * New accounts must replace the supplied initial PIN at first login. Existing
 * credentials are preserved unless an explicit reset is requested in the
 * protected credential file.
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
  let resetPin = false;
  if (args.length === 1) {
    const credentials = JSON.parse(readFileSync(args[0]!, 'utf8')) as { phone?: unknown; pin?: unknown; resetPin?: unknown };
    rawPhone = typeof credentials.phone === 'string' ? credentials.phone : undefined;
    pin = typeof credentials.pin === 'string' ? credentials.pin : undefined;
    resetPin = credentials.resetPin === true;
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
    const data = {
      fullName: 'Retail OS Super Admin',
      role: 'SUPER_ADMIN' as const,
      active: true,
      ...(resetPin
        ? {
            pinHash,
            mustChangePin: true,
          }
        : {}),
    };
    await prisma.user.update({
      where: { id: existing.id },
      data,
    });
    console.log(
      JSON.stringify({
        ok: true,
        created: false,
        resetPin,
        role: 'SUPER_ADMIN',
      }),
    );
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
  console.log(JSON.stringify({ ok: true, created: true, resetPin, role: 'SUPER_ADMIN' }));
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
