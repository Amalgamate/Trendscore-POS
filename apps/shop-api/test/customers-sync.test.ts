import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { customersRouter } from '../src/modules/customers/customers.router';

const ids = vi.hoisted(() => ({
  business: '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa',
  customer: '3be2eb75-15a1-437d-890a-32f517357a4e',
  user: 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f',
}));

const mocks = vi.hoisted(() => {
  const tx = {
    $queryRaw: vi.fn().mockResolvedValue([]),
    customer: {
      findFirst: vi.fn(),
      update: vi.fn().mockResolvedValue({}),
    },
    customerPayment: {
      create: vi.fn().mockResolvedValue({ id: 'payment-id' }),
    },
    cashSession: {
      findFirst: vi.fn().mockResolvedValue({ id: 'session-id' }),
      updateMany: vi.fn().mockResolvedValue({ count: 1 }),
    },
    customerLedger: {
      create: vi.fn(),
      findMany: vi.fn().mockResolvedValue([]),
      count: vi.fn().mockResolvedValue(0),
    },
  };
  const prisma = {
    user: { findUnique: vi.fn() },
    customer: { findMany: vi.fn(), count: vi.fn(), findFirst: vi.fn() },
    customerLedger: { findMany: vi.fn(), count: vi.fn() },
    $queryRaw: vi.fn(),
    $transaction: vi.fn((callback: (value: typeof tx) => unknown) => callback(tx)),
  };
  return { tx, prisma };
});

vi.mock('../src/lib/prisma', () => ({ prisma: mocks.prisma }));

const secret = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';
const token = jwt.sign({ sub: ids.user }, secret);

describe('customer credit synchronisation', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ids.user,
      fullName: 'Test Cashier',
      role: 'CASHIER',
      active: true,
      mustChangePin: false,
    });
    mocks.tx.customer.findFirst.mockResolvedValue({ id: ids.customer, balance: '100.00' });
    mocks.tx.customerLedger.create.mockImplementation(({ data }: { data: Record<string, unknown> }) => ({
      id: 'ledger-id', ...data, createdAt: new Date('2026-11-03T08:00:00Z'),
    }));
    mocks.tx.cashSession.findFirst.mockResolvedValue({ id: 'session-id' });
    const app = express();
    app.use(express.json());
    app.use('/customers', customersRouter(ids.business));
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

  async function postPayment(method: string, reference?: string) {
    return fetch(`${baseUrl}/customers/${ids.customer}/payments`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount: 25, method, ...(reference ? { reference } : {}) }),
    });
  }

  it('generates a payment reference and links payment and ledger atomically', async () => {
    const response = await postPayment('CASH');
    const body = await response.json() as { payment: { reference: string; entityId: string }; newBalance: number };
    expect(response.status).toBe(201);
    expect(body.newBalance).toBe(75);
    expect(body.payment.reference).toMatch(/^PAY-\d{8}-[A-F0-9]{8}$/);
    expect(mocks.tx.customerPayment.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ reference: body.payment.reference }),
    });
    expect(mocks.tx.customerLedger.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ entityId: 'payment-id', reference: body.payment.reference }),
    });
  });

  it('adds cash debt receipts to the open cashier session only for cash', async () => {
    await postPayment('CASH', 'CASH-RCPT');
    expect(mocks.tx.cashSession.updateMany).toHaveBeenCalledWith({
      where: { id: 'session-id', status: 'OPEN' },
      data: { debtPayments: { increment: expect.anything() } },
    });
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockResolvedValue({ id: ids.user, fullName: 'Test', role: 'CASHIER', active: true, mustChangePin: false });
    mocks.tx.customer.findFirst.mockResolvedValue({ id: ids.customer, balance: '100.00' });
    mocks.tx.customerLedger.create.mockResolvedValue({ id: 'ledger-id', amount: 25, balance: 75, reference: 'MPESA-RCPT', createdAt: new Date() });
    mocks.tx.cashSession.findFirst.mockResolvedValue({ id: 'session-id' });
    await postPayment('MPESA', 'MPESA-RCPT');
    expect(mocks.tx.cashSession.updateMany).not.toHaveBeenCalled();
  });

  it('pages the statement and includes ledger entity details', async () => {
    mocks.prisma.customerLedger.findMany.mockResolvedValue([{
      id: 'ledger-1', entryType: 'DEBIT', amount: 10, balance: 10,
      reference: 'REC-1', note: 'Sale', entityType: 'SALE', entityId: 'sale-id',
      createdAt: new Date('2026-11-03T08:00:00Z'),
    }]);
    mocks.prisma.customerLedger.count.mockResolvedValue(101);
    const response = await fetch(`${baseUrl}/customers/${ids.customer}/ledger?page=2&limit=10`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const body = await response.json() as { data: Array<Record<string, unknown>>; meta: Record<string, unknown> };
    expect(response.status).toBe(200);
    expect(mocks.prisma.customerLedger.findMany).toHaveBeenCalledWith(expect.objectContaining({ skip: 10, take: 10 }));
    expect(body.meta).toMatchObject({ total: 101, page: 2, limit: 10, hasMore: true });
    expect(body.data[0]).toMatchObject({ entityType: 'SALE', entityId: 'sale-id', note: 'Sale' });
  });

  it('returns balance versus ledger mismatches for the business', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ids.user, fullName: 'Test Owner', role: 'OWNER', active: true, mustChangePin: false,
    });
    mocks.prisma.$queryRaw.mockResolvedValue([
      { id: ids.customer, fullName: 'Test Customer', balance: '100.00', ledgerSum: '80.00' },
    ]);
    const response = await fetch(`${baseUrl}/customers/reconcile`, {
      headers: { Authorization: `Bearer ${jwt.sign({ sub: ids.user }, secret)}` },
    });
    const body = await response.json() as { count: number; mismatches: Array<Record<string, unknown>> };
    expect(response.status).toBe(200);
    expect(body.count).toBe(1);
    expect(body.mismatches[0]).toMatchObject({ balance: 100, ledgerSum: 80, drift: 20 });
  });

  it('returns an empty reconciliation result when all customer balances match the ledger', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ids.user, fullName: 'Test Owner', role: 'OWNER', active: true, mustChangePin: false,
    });
    mocks.prisma.$queryRaw.mockResolvedValue([]);
    const response = await fetch(`${baseUrl}/customers/reconcile`, {
      headers: { Authorization: `Bearer ${jwt.sign({ sub: ids.user }, secret)}` },
    });
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ mismatches: [], count: 0 });
  });

  it('rejects a payment when the customer does not exist without writing records', async () => {
    mocks.tx.customer.findFirst.mockResolvedValue(null);
    const response = await postPayment('CASH');
    expect(response.status).toBe(404);
    expect(mocks.tx.customer.update).not.toHaveBeenCalled();
    expect(mocks.tx.customerPayment.create).not.toHaveBeenCalled();
    expect(mocks.tx.customerLedger.create).not.toHaveBeenCalled();
  });

  it('does not allow a cashier to change customer credit terms', async () => {
    const response = await fetch(`${baseUrl}/customers/${ids.customer}`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ creditLimit: 500 }),
    });
    expect(response.status).toBe(403);
    expect(mocks.prisma.customer.findMany).not.toHaveBeenCalled();
  });
});
