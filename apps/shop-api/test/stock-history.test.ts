import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { stockRouter } from '../src/modules/stock/stock.router';

const mocks = vi.hoisted(() => ({
  userFindUnique: vi.fn(), movementFindMany: vi.fn(), movementCount: vi.fn(),
  queryRaw: vi.fn(), productFindFirst: vi.fn(), productUpdate: vi.fn(), movementCreate: vi.fn(), auditCreate: vi.fn(),
}));
vi.mock('../src/lib/prisma', () => ({ prisma: {
  user: { findUnique: mocks.userFindUnique },
  stockMovement: { findMany: mocks.movementFindMany, count: mocks.movementCount },
  $transaction: (callback: (tx: unknown) => unknown) => callback({
    $queryRaw: mocks.queryRaw, product: { findFirst: mocks.productFindFirst, update: mocks.productUpdate },
    stockMovement: { create: mocks.movementCreate }, auditLog: { create: mocks.auditCreate },
  }),
} }));

const business = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const user = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';
const token = jwt.sign({ sub: user }, process.env.JWT_SECRET ?? 'dev-secret-change-in-production');

describe('stock movement history', () => {
  let server: Server;
  let baseUrl: string;
  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.userFindUnique.mockResolvedValue({ id: user, fullName: 'Stock Clerk', role: 'STOCK_CLERK', active: true, mustChangePin: false });
    mocks.movementFindMany.mockResolvedValue([{
      id: 'move-1', productId: 'product-1', product: { id: 'product-1', name: 'Oil', sku: 'OIL', unit: 'L' },
      type: 'ADJUSTMENT_OUT', quantity: '-0.25', balanceAfter: '19.75', reason: 'SPILLAGE', note: null,
      reference: null, createdAt: new Date('2026-11-03T08:00:00Z'), createdBy: { id: user, fullName: 'Stock Clerk' },
    }]);
    mocks.movementCount.mockResolvedValue(1);
    mocks.productFindFirst.mockResolvedValue({ id: 'product-1', stock: '20.000' });
    mocks.productUpdate.mockResolvedValue({});
    mocks.movementCreate.mockResolvedValue({ id: 'count-movement' });
    mocks.auditCreate.mockResolvedValue({ id: 'audit-entry' });
    const app = express(); app.use(express.json()); app.use('/stock', stockRouter(business));
    server = createServer(app); await new Promise<void>((resolve) => server.listen(0, resolve));
    const address = server.address(); if (!address || typeof address === 'string') throw new Error('No test server address');
    baseUrl = `http://127.0.0.1:${address.port}`;
  });
  afterEach(async () => { await new Promise<void>((resolve, reject) => server.close((err) => err ? reject(err) : resolve())); });

  it('returns paged movement details and applies business-scoped filters', async () => {
    const response = await fetch(`${baseUrl}/stock/movements?productId=${'3be2eb75-15a1-437d-890a-32f517357a4e'}&type=ADJUSTMENT_OUT&page=2&limit=10`, { headers: { Authorization: `Bearer ${token}` } });
    expect(response.status).toBe(200);
    const body = await response.json() as { items: Array<Record<string, unknown>>; page: number; total: number };
    expect(body.page).toBe(2); expect(body.total).toBe(1);
    expect(body.items[0]).toMatchObject({ productName: 'Oil', quantity: -0.25, balanceAfter: 19.75, reason: 'SPILLAGE', createdBy: 'Stock Clerk' });
    expect(mocks.movementFindMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ businessId: business, type: 'ADJUSTMENT_OUT' }), skip: 10, take: 10 }));
  });

  it('records a physical count as an append-only adjustment and audit entry', async () => {
    const productId = '3be2eb75-15a1-437d-890a-32f517357a4e';
    const response = await fetch(`${baseUrl}/stock/count`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ productId, countedQuantity: 19.75, reason: 'Physical count variance' }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ previousQuantity: 20, countedQuantity: 19.75, delta: -0.25, movementId: 'count-movement' });
    const update = mocks.productUpdate.mock.calls[0]?.[0] as { data: { stock: { toString(): string } } };
    expect(update.data.stock.toString()).toBe('19.75');
    expect((mocks.productUpdate.mock.calls[0]?.[0] as { data: { varianceFlag: boolean } }).data.varianceFlag).toBe(false);
    expect(mocks.movementCreate).toHaveBeenCalledWith({ data: expect.objectContaining({ businessId: business, productId: 'product-1', type: 'ADJUSTMENT_OUT', reason: 'CORRECTION', note: 'Physical count variance' }) });
    expect(mocks.auditCreate).toHaveBeenCalledWith({ data: expect.objectContaining({ action: 'STOCK_COUNT_ADJUSTED', entityId: 'product-1' }) });
  });

  it('audits a matching count and clears a resolved variance without inventing a movement', async () => {
    mocks.productFindFirst.mockResolvedValue({ id: 'product-1', stock: '19.75', varianceFlag: true });
    const response = await fetch(`${baseUrl}/stock/count`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ productId: '3be2eb75-15a1-437d-890a-32f517357a4e', countedQuantity: 19.75, reason: 'Physical count confirmed' }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ delta: 0, movementId: null });
    expect(mocks.productUpdate).toHaveBeenCalledWith({ where: { id: 'product-1' }, data: { stock: expect.anything(), varianceFlag: false } });
    expect(mocks.movementCreate).not.toHaveBeenCalled();
    expect(mocks.auditCreate).toHaveBeenCalledWith({ data: expect.objectContaining({ action: 'STOCK_COUNT_CONFIRMED', entityId: 'product-1' }) });
  });
});
