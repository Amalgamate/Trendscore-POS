import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { Prisma } from '@prisma/client';
import { salesRouter } from '../src/modules/sales/sales.router';

const mocks = vi.hoisted(() => ({
  userFindUnique: vi.fn(),
  saleFindFirstOrThrow: vi.fn(),
  saleUpdateMany: vi.fn(),
  productUpdate: vi.fn(),
  movementCreate: vi.fn(),
  auditCreate: vi.fn(),
  queryRaw: vi.fn(),
}));

vi.mock('../src/lib/prisma', () => ({
  prisma: {
    user: { findUnique: mocks.userFindUnique },
    $transaction: (callback: (tx: unknown) => unknown) =>
      callback({
        $queryRaw: mocks.queryRaw,
        sale: {
          findFirstOrThrow: mocks.saleFindFirstOrThrow,
          updateMany: mocks.saleUpdateMany,
        },
        product: { update: mocks.productUpdate },
        stockMovement: { create: mocks.movementCreate },
        auditLog: { create: mocks.auditCreate },
      }),
  },
}));

const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const managerId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';
const productId = '3be2eb75-15a1-437d-890a-32f517357a4e';
const saleId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const token = jwt.sign(
  { sub: managerId },
  process.env.JWT_SECRET ?? 'dev-secret-change-in-production',
);

describe('measured sale reversal', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.userFindUnique.mockResolvedValue({
      id: managerId,
      role: 'MANAGER',
      active: true,
      mustChangePin: false,
    });
    mocks.saleFindFirstOrThrow.mockResolvedValue({
      id: saleId,
      businessId,
      receiptNumber: 'REC-TEST-250ML',
      status: 'COMPLETED',
      total: '75.00',
      customerId: null,
      customer: null,
      storefrontOrder: null,
      items: [{ productId, quantity: new Prisma.Decimal('0.25') }],
      payments: [],
    });
    mocks.saleUpdateMany.mockResolvedValue({ count: 1 });
    mocks.productUpdate.mockResolvedValue({ stock: new Prisma.Decimal('20.000') });
    mocks.movementCreate.mockResolvedValue({ id: 'return-movement' });
    mocks.auditCreate.mockResolvedValue({ id: 'reversal-audit' });
    const app = express();
    app.use(express.json());
    app.use('/sales', salesRouter(businessId));
    server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('No test server address');
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  });

  it('restores measured base quantity exactly and records the return movement', async () => {
    const response = await fetch(`${baseUrl}/sales/${saleId}/reverse`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: 'Customer return' }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ reversed: true, saleId });
    const stockUpdate = mocks.productUpdate.mock.calls[0]?.[0] as {
      data: { stock: { increment: Prisma.Decimal } };
    };
    expect(stockUpdate.data.stock.increment.toString()).toBe('0.25');
    const movement = mocks.movementCreate.mock.calls[0]?.[0] as {
      data: { type: string; quantity: Prisma.Decimal; balanceAfter: Prisma.Decimal };
    };
    expect(movement.data.type).toBe('RETURN_FROM_CUSTOMER');
    expect(movement.data.quantity.toString()).toBe('0.25');
    expect(movement.data.balanceAfter.toString()).toBe('20');
    expect(mocks.auditCreate).toHaveBeenCalledWith({
      data: expect.objectContaining({ action: 'SALE_REVERSED', entityId: saleId }),
    });
  });

  it('claims reversal once so concurrent/retried requests cannot restore stock twice', async () => {
    mocks.saleUpdateMany.mockResolvedValue({ count: 0 });
    const response = await fetch(`${baseUrl}/sales/${saleId}/reverse`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason: 'Retry' }),
    });
    expect(response.status).toBe(409);
    expect(mocks.productUpdate).not.toHaveBeenCalled();
    expect(mocks.movementCreate).not.toHaveBeenCalled();
  });
});
