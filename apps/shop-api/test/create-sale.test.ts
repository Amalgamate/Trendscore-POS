import { describe, expect, it, vi } from 'vitest';
import type { PrismaClient } from '@prisma/client';
import { createSale } from '../src/modules/sales/create-sale';

const productId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const customerId = '3be2eb75-15a1-437d-890a-32f517357a4e';
const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const cashierId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';

function makePrisma() {
  const customer = {
    id: customerId,
    status: 'ACTIVE',
    creditFrozen: false,
    balance: 0,
    creditLimit: 500,
  };
  const tx = {
    $queryRaw: vi.fn().mockResolvedValue([]),
    sale: {
      findUnique: vi.fn().mockResolvedValue(null),
      count: vi.fn().mockResolvedValue(0),
      create: vi
        .fn()
        .mockResolvedValue({ id: 'sale-id', receiptNumber: 'REC-TEST-0001' }),
    },
    product: {
      findMany: vi.fn().mockResolvedValue([
        {
          id: productId,
          name: 'Tea',
          salePrice: 100,
          costPrice: 50,
          vatRate: 0.16,
          stock: 3,
          active: true,
        },
      ]),
      update: vi.fn().mockResolvedValue({}),
    },
    saleItem: { create: vi.fn().mockResolvedValue({}) },
    stockMovement: { create: vi.fn().mockResolvedValue({}) },
    salePayment: { create: vi.fn().mockResolvedValue({}) },
    customer: {
      findFirst: vi.fn().mockResolvedValue(customer),
      findUniqueOrThrow: vi.fn().mockResolvedValue(customer),
      update: vi.fn().mockResolvedValue({}),
    },
    customerLedger: { create: vi.fn().mockResolvedValue({}) },
  };
  const client = {
    $transaction: vi.fn(
      async (callback: (transaction: typeof tx) => Promise<unknown>) =>
        callback(tx),
    ),
  } as unknown as PrismaClient;
  return { client, tx };
}

function input(
  method: 'CASH' | 'MPESA' | 'CREDIT',
  extra: Record<string, unknown> = {},
) {
  return {
    businessId,
    cashierId,
    idempotencyKey: `test-${method.toLowerCase()}`,
    method,
    lines: [{ productId, quantity: 1 }],
    ...extra,
  };
}

describe('createSale payment methods', () => {
  it('records M-Pesa Till payments as pending with their till reference', async () => {
    const { client, tx } = makePrisma();

    const result = await createSale(
      client,
      input('MPESA', { paymentReference: 'TILL: 123456' }),
    );

    expect(result.paymentStatus).toBe('PENDING');
    expect(tx.salePayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        method: 'MPESA',
        status: 'PENDING',
        reference: 'TILL: 123456',
        settledAt: null,
      }),
    });
  });

  it('stores cash tender and computes change from the server total', async () => {
    const { client, tx } = makePrisma();

    const result = await createSale(client, input('CASH', { cashTendered: 120 }));

    expect(result.paymentStatus).toBe('SUCCESS');
    expect(tx.salePayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        method: 'CASH',
        status: 'SUCCESS',
        cashTendered: 120,
        changeDue: 20,
      }),
    });
  });

  it('posts credit sales to the active customer ledger', async () => {
    const { client, tx } = makePrisma();

    const result = await createSale(
      client,
      input('CREDIT', { customerId }),
    );

    expect(result.paymentStatus).toBe('SUCCESS');
    expect(tx.customerLedger.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        customerId,
        entryType: 'DEBIT',
        entityType: 'SALE',
      }),
    });
  });

  it('rejects an M-Pesa sale without a Till reference', async () => {
    const { client } = makePrisma();

    await expect(createSale(client, input('MPESA'))).rejects.toThrow(
      'Enter the M-Pesa Till number before recording this sale.',
    );
  });
});
