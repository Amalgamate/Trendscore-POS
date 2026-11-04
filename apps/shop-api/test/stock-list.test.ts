import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { productsRouter } from '../src/modules/products/products.router';

const mocks = vi.hoisted(() => ({
  userFindUnique: vi.fn(),
  productFindMany: vi.fn(),
  productCount: vi.fn(),
}));

vi.mock('../src/lib/prisma', () => ({
  prisma: {
    user: { findUnique: mocks.userFindUnique },
    product: { findMany: mocks.productFindMany, count: mocks.productCount },
  },
}));

const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const cashierId = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';
const token = jwt.sign(
  { sub: cashierId },
  process.env.JWT_SECRET ?? 'dev-secret-change-in-production',
);

describe('stock audit list', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();
    mocks.userFindUnique.mockResolvedValue({
      id: cashierId,
      role: 'CASHIER',
      active: true,
      mustChangePin: false,
    });
    mocks.productFindMany.mockResolvedValue([
      {
        id: 'oil-id',
        name: 'Cooking oil',
        sku: 'OIL-1',
        barcode: null,
        category: { name: 'Cooking' },
        stock: '2.500',
        unit: 'l',
        salePrice: '300.00',
        costPrice: '250.00',
        lowStockThreshold: '1.000',
        varianceFlag: false,
      },
      {
        id: 'flour-id',
        name: 'Flour',
        sku: 'FLOUR-1',
        barcode: null,
        category: { name: 'Baking' },
        stock: '1.250',
        unit: 'kg',
        salePrice: '180.00',
        costPrice: '140.00',
        lowStockThreshold: '0.500',
        varianceFlag: false,
      },
    ]);
    mocks.productCount.mockResolvedValue(2);
    const app = express();
    app.use(express.json());
    app.use('/products', productsRouter(businessId));
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

  it('returns measured quantities, valuations and totals to cashier accounts', async () => {
    const response = await fetch(`${baseUrl}/products/stock/list`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(response.status).toBe(200);
    const body = await response.json() as {
      data: Array<Record<string, unknown>>;
      totals: Record<string, number>;
      valuationBasis: Record<string, string>;
    };
    expect(body.data).toHaveLength(2);
    expect(body.data[0]).toMatchObject({
      name: 'Cooking oil',
      quantity: 2.5,
      unit: 'l',
      costPrice: 250,
      valueAtCost: 625,
      valueAtSellingPrice: 750,
    });
    expect(body.totals).toEqual({
      quantity: 3.75,
      valueAtCost: 800,
      valueAtSellingPrice: 975,
    });
    expect(body.valuationBasis.valueAtSellingPrice).toContain('not realized revenue');
    expect(mocks.productFindMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ businessId, active: true }) }),
    );
  });
});
