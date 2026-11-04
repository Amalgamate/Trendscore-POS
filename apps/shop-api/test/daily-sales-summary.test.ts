import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { salesRouter } from '../src/modules/sales/sales.router';

const ids = vi.hoisted(() => ({
  business: '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa',
  user: 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f',
}));

const mocks = vi.hoisted(() => ({
  prisma: {
    user: { findUnique: vi.fn() },
    businessSetting: { findUnique: vi.fn() },
    sale: { aggregate: vi.fn(), count: vi.fn(), findMany: vi.fn() },
    salePayment: { findMany: vi.fn() },
    refund: { findMany: vi.fn() },
    customerPayment: { groupBy: vi.fn() },
  },
}));

vi.mock('../src/lib/prisma', () => ({ prisma: mocks.prisma }));

const secret = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';

describe('daily sales summary', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockImplementation(async () => ({
      id: ids.user,
      fullName: 'Test Owner',
      role: 'OWNER',
      active: true,
      mustChangePin: false,
    }));
    mocks.prisma.businessSetting.findUnique.mockResolvedValue(null);
    mocks.prisma.sale.aggregate
      .mockResolvedValueOnce({ _sum: { total: '100' } })
      .mockResolvedValueOnce({ _sum: { total: '100' } })
      .mockResolvedValue({ _sum: { vatAmount: '16' } });
    mocks.prisma.sale.count.mockResolvedValue(2);
    mocks.prisma.salePayment.findMany.mockResolvedValue([
      { method: 'CASH', amount: '30' },
      { method: 'MPESA', amount: '30' },
      { method: 'CREDIT', amount: '40' },
    ]);
    mocks.prisma.refund.findMany.mockResolvedValue([{ amount: '10' }]);
    mocks.prisma.customerPayment.groupBy.mockResolvedValue([
      { method: 'CASH', _sum: { amount: '5' }, _count: { _all: 1 } },
      { method: 'MPESA', _sum: { amount: '7' }, _count: { _all: 2 } },
    ]);
    const app = express();
    app.use('/sales', salesRouter(ids.business));
    server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, resolve));
    const address = server.address();
    if (!address || typeof address === 'string') throw new Error('No test server address');
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) =>
      server.close((error) => error ? reject(error) : resolve()),
    );
  });

  async function getSummary(date = '2026-11-03', role = 'OWNER') {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ids.user, fullName: 'Test User', role, active: true, mustChangePin: false,
    });
    const token = jwt.sign({ sub: ids.user }, secret);
    const response = await fetch(`${baseUrl}/sales/summary?date=${date}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    return { response, body: await response.json() as { today: Record<string, unknown> } };
  }

  it('uses business timezone day bounds, summarizes payments, refunds, credit, voids and debt receipts', async () => {
    const { response, body } = await getSummary();
    expect(response.status).toBe(200);
    expect(mocks.prisma.sale.aggregate).toHaveBeenCalledTimes(3);
    const firstAggregate = mocks.prisma.sale.aggregate.mock.calls[0]![0];
    const creditAggregate = mocks.prisma.sale.aggregate.mock.calls[1]![0];
    const vatAggregate = mocks.prisma.sale.aggregate.mock.calls[2]![0];
    expect(firstAggregate.where.createdAt).toEqual({
      gte: new Date('2026-11-02T21:00:00.000Z'),
      lt: new Date('2026-11-03T21:00:00.000Z'),
    });
    expect(firstAggregate.where.status).toEqual({ in: ['COMPLETED', 'PARTIALLY_REFUNDED'] });
    expect(creditAggregate.where.payments.some.method).toBe('CREDIT');
    expect(vatAggregate._sum.vatAmount).toBe(true);
    expect(body.today).toMatchObject({
      date: '2026-11-03',
      timezone: 'Africa/Nairobi',
      total: 100,
      count: 2,
      average: 50,
      byMethod: { CASH: 30, MPESA: 30, CREDIT: 40 },
      paymentTotal: 100,
      netSales: 90,
      refunds: { total: 10, count: 1 },
      voidedCount: 2,
      creditGiven: 100,
      debtPayments: {
        CASH: { amount: 5, count: 1 },
        MPESA: { amount: 7, count: 2 },
      },
    });
  });

  it('uses the saved business timezone and scopes cashiers to their own sales and receipts', async () => {
    mocks.prisma.businessSetting.findUnique.mockResolvedValue({ value: 'America/New_York' });
    await getSummary('2026-11-03', 'CASHIER');
    const aggregateWhere = mocks.prisma.sale.aggregate.mock.calls[0]![0].where;
    expect(aggregateWhere.cashierId).toBe(ids.user);
    expect(aggregateWhere.createdAt).toEqual({
      gte: new Date('2026-11-03T05:00:00.000Z'),
      lt: new Date('2026-11-04T05:00:00.000Z'),
    });
    const debtQuery = mocks.prisma.customerPayment.groupBy.mock.calls[0]![0];
    expect(debtQuery.where.receivedById).toBe(ids.user);
  });

  it('rejects impossible calendar dates', async () => {
    const { response } = await getSummary('2026-02-30');
    expect(response.status).toBe(422);
  });
});
