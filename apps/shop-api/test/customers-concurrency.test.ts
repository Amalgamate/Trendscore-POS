import type { PrismaClient } from '@prisma/client';
import { describe, expect, it, vi } from 'vitest';
import { createSale } from '../src/modules/sales/create-sale';
import { SaleValidationError } from '../src/modules/sales/pricing';

const productId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const customerId = '3be2eb75-15a1-437d-890a-32f517357a4e';
const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const cashierId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';

function makeTransaction(customer: { balance: number; creditLimit: number }) {
  const tx = {
    $queryRaw: vi.fn().mockResolvedValue([]),
    sale: {
      findUnique: vi.fn().mockResolvedValue(null),
      count: vi.fn().mockResolvedValue(0),
      create: vi.fn().mockImplementation(async () => ({
        id: `sale-${Math.random()}`,
        receiptNumber: `REC-${Math.random()}`,
      })),
    },
    product: {
      findMany: vi.fn().mockResolvedValue([{
        id: productId,
        name: 'Tea',
        salePrice: 500,
        costPrice: 200,
        vatRate: 0,
        stock: 20,
        active: true,
      }]),
      update: vi.fn().mockResolvedValue({}),
      updateMany: vi.fn().mockResolvedValue({ count: 1 }),
    },
    saleItem: { create: vi.fn().mockResolvedValue({}) },
    stockMovement: { create: vi.fn().mockResolvedValue({}) },
    salePayment: { create: vi.fn().mockResolvedValue({}) },
    customer: {
      findFirst: vi.fn().mockImplementation(async () => ({
        id: customerId,
        fullName: 'Amina Wanjiku',
        status: 'ACTIVE',
        creditFrozen: false,
        balance: customer.balance,
        creditLimit: customer.creditLimit,
      })),
      findUniqueOrThrow: vi.fn().mockImplementation(async () => ({
        id: customerId,
        balance: customer.balance,
        creditLimit: customer.creditLimit,
      })),
      update: vi.fn().mockImplementation(async ({ data }: { data: { balance: number } }) => {
        customer.balance = Number(data.balance);
        return {};
      }),
    },
    customerLedger: { create: vi.fn().mockResolvedValue({}) },
  };
  const client = {
    $transaction: vi.fn(async (callback: (transaction: typeof tx) => Promise<unknown>) => callback(tx)),
  } as unknown as PrismaClient;
  return { client, tx };
}

function creditSale(key: string) {
  return {
    businessId,
    cashierId,
    idempotencyKey: key,
    method: 'CREDIT' as const,
    customerId,
    lines: [{ productId, quantity: 1 }],
  };
}

describe('customer credit concurrency protections', () => {
  it('takes a row lock before validating the balance and credit limit', async () => {
    const customer = { balance: 0, creditLimit: 500 };
    const { client, tx } = makeTransaction(customer);

    await createSale(client, creditSale('credit-lock-test'));

    expect(tx.$queryRaw).toHaveBeenCalledTimes(2);
    expect(tx.$queryRaw.mock.invocationCallOrder[1]!).toBeLessThan(
      tx.customer.findFirst.mock.invocationCallOrder[0]!,
    );
    expect(tx.customer.update).toHaveBeenCalledOnce();
    const update = tx.customer.update.mock.calls[0]![0] as {
      where: { id: string };
      data: { balance: { toString(): string } };
    };
    expect(update.where.id).toBe(customerId);
    expect(update.data.balance.toString()).toBe('500');
  });

  it('rejects a concurrent sale after the locked account reaches its limit', async () => {
    const customer = { balance: 600, creditLimit: 750 };
    const { client, tx } = makeTransaction(customer);
    await expect(createSale(client, creditSale('credit-first'))).rejects.toMatchObject({
      rejection: {
        kind: 'CREDIT_LIMIT_EXCEEDED',
        customerId,
        available: 15000,
        requested: 50000,
      },
    } satisfies Partial<SaleValidationError>);
    expect(tx.customer.update).not.toHaveBeenCalled();
    expect(customer.balance).toBe(600);
  });
});
