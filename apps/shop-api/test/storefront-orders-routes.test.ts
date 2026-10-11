import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { storefrontOrdersRouter } from '../src/modules/storefront/storefront-orders.router';

const mocks = vi.hoisted(() => ({
  prisma: {
    user: { findUnique: vi.fn() },
    storefrontOrder: {
      findMany: vi.fn(),
      count: vi.fn(),
      findFirst: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
    },
    product: { update: vi.fn() },
    stockMovement: { create: vi.fn() },
    storefrontOrderEvent: { create: vi.fn() },
    $queryRaw: vi.fn(),
    $transaction: vi.fn(),
  },
}));

vi.mock('../src/lib/prisma', () => ({ prisma: mocks.prisma }));

const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const userId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';
const productId = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const orderId = 'ab674c37-1be4-4cb7-a7d0-850ab680bb86';
const expiresAt = new Date(Date.now() + 60_000);

function sampleOrder(status = 'AWAITING_PAYMENT') {
  return {
    id: orderId,
    businessId,
    orderNumber: 'WEB-TEST',
    status,
    fulfillmentMethod: 'PICKUP',
    deliveryAddress: null,
    subtotal: 100,
    total: 100,
    expiresAt,
    createdAt: new Date(),
    customerName: 'Amina Wanjiku',
    customerPhone: '+254712345678',
    customerEmail: null,
    items: [
      {
        productId,
        productName: 'Tea',
        variantLabel: null,
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
        unitCost: 50,
      },
    ],
    statusEvents: [],
  };
}

describe('staff storefront order routes', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: userId,
      fullName: 'Test Cashier',
      role: 'CASHIER',
      active: true,
      mustChangePin: false,
    });
    const app = express();
    app.use(express.json());
    app.use('/storefront/orders', storefrontOrdersRouter(businessId));
    server = createServer(app);
    await new Promise<void>((resolve) => {
      server.listen(0, resolve);
    });
    const address = server.address();
    if (!address || typeof address === 'string') {
      throw new Error('Test server did not bind to a TCP port.');
    }
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  });

  function authHeaders() {
    const token = jwt.sign(
      { sub: userId },
      process.env.JWT_SECRET ?? 'dev-secret-change-in-production',
    );
    return { Authorization: `Bearer ${token}` };
  }

  it('requires authentication before exposing the staff order queue', async () => {
    const response = await fetch(`${baseUrl}/storefront/orders`);
    expect(response.status).toBe(401);
    expect(mocks.prisma.storefrontOrder.findMany).not.toHaveBeenCalled();
  });

  it('returns a paginated order queue to authorized staff', async () => {
    mocks.prisma.storefrontOrder.findMany
      .mockResolvedValueOnce([])
      .mockResolvedValueOnce([sampleOrder()]);
    mocks.prisma.storefrontOrder.count.mockResolvedValue(1);

    const response = await fetch(
      `${baseUrl}/storefront/orders?status=AWAITING_PAYMENT&page=1&limit=25`,
      { headers: authHeaders() },
    );
    const payload = (await response.json()) as {
      data: Array<{ customerName: string }>;
      meta: { total: number; page: number; limit: number };
    };

    expect(response.status).toBe(200);
    expect(payload.data).toHaveLength(1);
    expect(payload.data[0]?.customerName).toBe('Amina Wanjiku');
    expect(payload.meta).toEqual({ total: 1, page: 1, limit: 25 });
    expect(mocks.prisma.storefrontOrder.findMany).toHaveBeenLastCalledWith(
      expect.objectContaining({
        where: { businessId, status: 'AWAITING_PAYMENT' },
        skip: 0,
        take: 25,
      }),
    );
  });

  it('does not expose customer order details to stock clerks', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: userId,
      fullName: 'Stock Clerk',
      role: 'STOCK_CLERK',
      active: true,
      mustChangePin: false,
    });

    const response = await fetch(`${baseUrl}/storefront/orders`, {
      headers: authHeaders(),
    });

    expect(response.status).toBe(403);
    expect(mocks.prisma.storefrontOrder.findMany).not.toHaveBeenCalled();
  });

  it('cancels a pending order once and releases its stock hold', async () => {
    const pending = sampleOrder();
    const cancelled = {
      ...sampleOrder('CANCELLED'),
      statusEvents: [
        {
          fromStatus: 'AWAITING_PAYMENT',
          toStatus: 'CANCELLED',
          detail: 'Cancelled by Test Cashier. Reserved stock was released.',
          createdAt: new Date(),
        },
      ],
    };
    const transaction = {
      $queryRaw: vi.fn().mockResolvedValue([{ id: productId }]),
      storefrontOrder: {
        updateMany: vi.fn().mockResolvedValue({ count: 1 }),
        findUniqueOrThrow: vi.fn().mockResolvedValue(cancelled),
      },
      product: { update: vi.fn().mockResolvedValue({ stock: 5 }) },
      stockMovement: { create: vi.fn().mockResolvedValue({}) },
      storefrontOrderEvent: { create: vi.fn().mockResolvedValue({}) },
    };
    mocks.prisma.storefrontOrder.findMany.mockResolvedValue([]);
    mocks.prisma.storefrontOrder.findFirst.mockResolvedValue(pending);
    mocks.prisma.$transaction.mockImplementation((callback) =>
      callback(transaction),
    );

    const response = await fetch(
      `${baseUrl}/storefront/orders/${orderId}/cancel`,
      { method: 'PATCH', headers: authHeaders() },
    );
    const payload = (await response.json()) as {
      data: { status: string };
    };

    expect(response.status).toBe(200);
    expect(payload.data.status).toBe('CANCELLED');
    expect(transaction.product.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: productId },
        data: { stock: { increment: 1 } },
      }),
    );
    expect(transaction.stockMovement.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          type: 'STOREFRONT_RELEASE',
          quantity: 1,
          reference: 'WEB-TEST',
          createdById: userId,
        }),
      }),
    );
    expect(transaction.storefrontOrderEvent.create).toHaveBeenCalledOnce();
  });

  it('does not release stock again when a cancelled order is retried', async () => {
    const transaction = {
      $queryRaw: vi.fn().mockResolvedValue([{ id: productId }]),
      storefrontOrder: {
        updateMany: vi.fn().mockResolvedValue({ count: 0 }),
        findUniqueOrThrow: vi.fn().mockResolvedValue(sampleOrder('CANCELLED')),
      },
      product: { update: vi.fn() },
      stockMovement: { create: vi.fn() },
      storefrontOrderEvent: { create: vi.fn() },
    };
    mocks.prisma.storefrontOrder.findMany.mockResolvedValue([]);
    mocks.prisma.storefrontOrder.findFirst.mockResolvedValue(sampleOrder());
    mocks.prisma.$transaction.mockImplementation((callback) =>
      callback(transaction),
    );

    const response = await fetch(
      `${baseUrl}/storefront/orders/${orderId}/cancel`,
      { method: 'PATCH', headers: authHeaders() },
    );

    expect(response.status).toBe(200);
    expect(transaction.product.update).not.toHaveBeenCalled();
    expect(transaction.stockMovement.create).not.toHaveBeenCalled();
    expect(transaction.storefrontOrderEvent.create).not.toHaveBeenCalled();
  });
});
