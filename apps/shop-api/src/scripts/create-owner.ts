/**
 * Create the owner user for a freshly provisioned shop instance.
 *
 * Called by the provisioning engine:
 *   node dist/create-owner.js "James Kamau" 254712345678 1234
 *
 * Idempotent on purpose. Provisioning supports resume, so this may run
 * twice for the same shop. Re-running must update the existing owner,
 * never create a second one — two owner accounts on one shop is a support
 * incident and a security problem.
 *
 * The PIN is hashed with argon2 and never logged. Nothing is printed that
 * could be used to authenticate.
 */
import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

const prisma = new PrismaClient();

/** Phone must be stored in E.164 form for M-Pesa to work later. */
function normalisePhone(input: string): string {
  const digits = input.replace(/[^\d]/g, '');
  if (digits.startsWith('254')) return digits;
  if (digits.startsWith('0')) return `254${digits.slice(1)}`;
  if (digits.startsWith('7') && digits.length === 9) return `254${digits}`;
  throw new Error(`Invalid phone number: ${input}`);
}

function validatePin(pin: string): string {
  if (!/^\d{4,6}$/.test(pin)) {
    throw new Error('PIN must be 4 to 6 digits');
  }
  return pin;
}

async function main(): Promise<void> {
  const [fullName, rawPhone, rawPin] = process.argv.slice(2);

  if (!fullName || !rawPhone || !rawPin) {
    throw new Error('Usage: create-owner.js <fullName> <phone> <pin>');
  }

  const phone = normalisePhone(rawPhone);
  const pin = validatePin(rawPin);

  const pinHash = await argon2.hash(pin, {
    type: argon2.argon2id,
    memoryCost: 19_456,
    timeCost: 2,
    parallelism: 1,
  });

  // Upsert by phone: the unique constraint is what makes this safe to retry.
  const owner = await prisma.user.upsert({
    where: { phone },
    update: { fullName, pinHash, role: 'OWNER', active: true },
    create: { fullName, phone, pinHash, role: 'OWNER', active: true },
  });

  // Never echo the PIN back; the provisioner already holds it.
  console.log(JSON.stringify({ ok: true, ownerId: owner.id, role: owner.role }));
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
