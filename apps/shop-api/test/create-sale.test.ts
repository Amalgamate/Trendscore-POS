import { describe, expect, it, vi } from 'vitest';
import argon2 from 'argon2';
import type { PrismaClient } from '@prisma/client';
import { createSale } from '../src/modules/sales/create-sale';

const productId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const customerId = '3be2eb75-15a1-437d-890a-32f517357a4e';
const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const cashierId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';

function makePrisma() {
  const customer = {
    id: customerId,
    fullName: 'Amina Wanjiku',
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
          unit: 'pc',
          vatRate: 0.16,
          stock: 3,
          active: true,
        },
      ]),
      update: vi.fn().mockResolvedValue({}),
      updateMany: vi.fn().mockResolvedValue({ count: 1 }),
    },
    saleItem: { create: vi.fn().mockResolvedValue({}) },
    stockMovement: { create: vi.fn().mockResolvedValue({}) },
    approval: { create: vi.fn().mockResolvedValue({}) },
    auditLog: { create: vi.fn().mockResolvedValue({}) },
    user: { findFirst: vi.fn() },
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
    expect(tx.$queryRaw).toHaveBeenCalledOnce();
    expect(tx.$queryRaw.mock.invocationCallOrder[0]!).toBeLessThan(
      tx.product.findMany.mock.invocationCallOrder[0]!,
    );
    expect(tx.salePayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        method: 'CASH',
        status: 'SUCCESS',
        cashTendered: 120,
        changeDue: 20,
      }),
    });
  });

  it('keeps the legacy whole-item till contract and snapshots its base unit', async () => {
    const { client, tx } = makePrisma();

    await createSale(client, input('CASH'));

    expect(tx.saleItem.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        quantity: 1,
        soldQuantity: 1,
        soldUnit: 'pc',
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

  it('stores a trimmed, typed customer name on a non-credit sale', async () => {
    const { client, tx } = makePrisma();

    await createSale(
      client,
      input('CASH', { customerName: '  Grace Njeri  ' }),
    );

    expect(tx.sale.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ customerName: 'Grace Njeri' }),
    });
  });

  it('snapshots the selected account name when no receipt name was typed', async () => {
    const { client, tx } = makePrisma();

    await createSale(client, input('CREDIT', { customerId }));

    expect(tx.sale.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ customerId, customerName: 'Amina Wanjiku' }),
    });
  });

  it('rejects a typed-name-only customer on credit sales', async () => {
    const { client } = makePrisma();

    await expect(
      createSale(client, input('CREDIT', { customerName: 'Grace Njeri' })),
    ).rejects.toMatchObject({ rejection: { kind: 'CUSTOMER_REQUIRED' } });
  });

  it('keeps customerName empty when no customer name was supplied', async () => {
    const { client, tx } = makePrisma();

    await createSale(client, input('CASH'));

    expect(tx.sale.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ customerName: undefined }),
    });
  });

  it('allows a negative-stock sale only with a valid Owner or Manager PIN and records the audit trail', async () => {
    const { client, tx } = makePrisma();
    const managerPinHash = await argon2.hash('2468');
    tx.user.findFirst.mockResolvedValue({
      id: 'manager-id',
      fullName: 'Shop Manager',
      pinHash: managerPinHash,
    });
    tx.product.findMany.mockResolvedValueOnce([
      {
        id: productId,
        name: 'Tea',
        salePrice: 100,
        costPrice: 50,
        vatRate: 0.16,
        stock: 0,
        active: true,
        unit: 'pc',
      },
    ]);
    tx.product.updateMany
      .mockResolvedValueOnce({ count: 0 })
      .mockResolvedValueOnce({ count: 1 });

    await createSale(
      client,
      input('CASH', {
        cashTendered: 100,
        stockOverride: { approverId: 'manager-id', pin: '2468' },
      }),
    );

    expect(tx.product.updateMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ data: { stock: { decrement: 1 }, varianceFlag: true } }),
    );
    expect(tx.stockMovement.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ type: 'SALE', quantity: -1, balanceAfter: expect.objectContaining({ s: -1 }) }),
    });
    expect(tx.approval.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        entityType: 'ADJUSTMENT',
        entityId: productId,
        status: 'APPROVED',
        requestedById: cashierId,
        approvedById: 'manager-id',
      }),
    });
    expect(tx.auditLog.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ action: 'STOCK_OVERRIDE_APPROVED', entityId: productId }),
    });
  });

  it('rejects an invalid manager PIN before writing a sale', async () => {
    const { client, tx } = makePrisma();
    tx.user.findFirst.mockResolvedValue({
      id: 'manager-id',
      fullName: 'Shop Manager',
      pinHash: await argon2.hash('9999'),
    });

    await expect(
      createSale(
        client,
        input('CASH', {
          cashTendered: 100,
          stockOverride: { approverId: 'manager-id', pin: '2468' },
        }),
      ),
    ).rejects.toMatchObject({ rejection: { kind: 'STOCK_OVERRIDE_DENIED' } });
    expect(tx.sale.create).not.toHaveBeenCalled();
  });

  it('does not offer a cashier account as a valid stock approver', async () => {
    const { client, tx } = makePrisma();
    tx.user.findFirst.mockResolvedValue(null);

    await expect(
      createSale(
        client,
        input('CASH', {
          cashTendered: 100,
          stockOverride: { approverId: 'cashier-id', pin: '2468' },
        }),
      ),
    ).rejects.toMatchObject({ rejection: { kind: 'STOCK_OVERRIDE_DENIED' } });
    expect(tx.user.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ role: { in: ['OWNER', 'MANAGER'] } }),
      }),
    );
    expect(tx.sale.create).not.toHaveBeenCalled();
  });
});
