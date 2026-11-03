import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import express from 'express';
import jwt from 'jsonwebtoken';
import { createServer, type Server } from 'node:http';
import { productsRouter } from '../src/modules/products/products.router';

// ─── Module-level mock for the Prisma singleton ──────────────────────────────

interface MockTx {
  $queryRaw: ReturnType<typeof vi.fn>;
  stockMovement: { deleteMany: ReturnType<typeof vi.fn> };
  product: { delete: ReturnType<typeof vi.fn> };
  auditLog: { create: ReturnType<typeof vi.fn> };
}

const mocks = vi.hoisted(() => {
  const tx: MockTx = {
    $queryRaw: vi.fn().mockResolvedValue([]),
    stockMovement: {
      deleteMany: vi.fn().mockResolvedValue({ count: 0 }),
    },
    product: {
      delete: vi.fn().mockResolvedValue({}),
    },
    auditLog: {
      create: vi.fn().mockResolvedValue({}),
    },
  };

  return {
    tx,
    prisma: {
      user: {
        findUnique: vi.fn(),
      },
      product: {
        findFirst: vi.fn(),
        update: vi.fn(),
      },
      saleItem: { count: vi.fn() },
      purchaseItem: { count: vi.fn() },
      refundItem: { count: vi.fn() },
      stockMovement: { deleteMany: vi.fn() },
      auditLog: { create: vi.fn() },
      $transaction: vi.fn((callback: (tx: MockTx) => Promise<unknown>) =>
        callback(tx),
      ),
    },
  };
});

vi.mock('../src/lib/prisma', () => ({ prisma: mocks.prisma }));

// ─── Test constants ───────────────────────────────────────────────────────────

const businessId = '2bda039f-a3c0-4ea3-bb84-9c9c0e908dfa';
const productId  = 'bfe1dba0-961f-4e11-9125-28875b9c3f8a';
const ownerId    = 'd91bf80e-60bf-46d3-8c29-aab8a3b2332f';
const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';

function makeToken(userId = ownerId) {
  return jwt.sign({ sub: userId }, JWT_SECRET);
}

/** A product row whose stock is a Prisma Decimal-like object (toString works). */
function makeProduct(overrides: Record<string, unknown> = {}) {
  return {
    id: productId,
    name: 'Test Product',
    sku: 'T-001',
    barcode: null,
    salePrice: { toString: () => '100.00' },
    costPrice: { toString: () => '60.00' },
    stock: { toString: () => '0' },
    active: true,
    ...overrides,
  };
}

// ─── Test server setup ────────────────────────────────────────────────────────

describe('DELETE /products/:id and POST /products/:id/archive', () => {
  let server: Server;
  let baseUrl: string;

  beforeEach(async () => {
    vi.clearAllMocks();

    // Default: authenticate as OWNER
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ownerId,
      fullName: 'Test Owner',
      role: 'OWNER',
      active: true,
      mustChangePin: false,
    });

    // Default: no history
    mocks.prisma.saleItem.count.mockResolvedValue(0);
    mocks.prisma.purchaseItem.count.mockResolvedValue(0);
    mocks.prisma.refundItem.count.mockResolvedValue(0);

    // Default: product exists with stock=0
    mocks.prisma.product.findFirst.mockResolvedValue(makeProduct());

    // Reset tx mocks
    mocks.tx.$queryRaw.mockResolvedValue([]);
    mocks.tx.stockMovement.deleteMany.mockResolvedValue({ count: 0 });
    mocks.tx.product.delete.mockResolvedValue({});
    mocks.tx.auditLog.create.mockResolvedValue({});

    const app = express();
    app.use(express.json());
    app.use('/products', productsRouter(businessId));

    server = createServer(app);
    await new Promise<void>((resolve) => server.listen(0, resolve));

    const address = server.address();
    if (!address || typeof address === 'string') {
      throw new Error('Test server did not bind to a TCP port.');
    }
    baseUrl = `http://127.0.0.1:${address.port}`;
  });

  afterEach(async () => {
    await new Promise<void>((resolve, reject) => {
      server.close((err) => (err ? reject(err) : resolve()));
    });
  });

  function authHeaders(token = makeToken()) {
    return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  }

  // ── 1. No history, zero stock → 200 deleted ──────────────────────────────
  it('deletes a product with no history and zero stock', async () => {
    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const body = (await res.json()) as { id: string; deleted: boolean };

    expect(res.status).toBe(200);
    expect(body).toEqual({ id: productId, deleted: true });
    expect(mocks.tx.stockMovement.deleteMany).toHaveBeenCalledWith({
      where: { productId },
    });
    expect(mocks.tx.product.delete).toHaveBeenCalledWith({ where: { id: productId } });
    expect(mocks.tx.auditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'PRODUCT_PURGE' }) }),
    );
  });

  // ── 2. Product with sale_items → 409 PRODUCT_HAS_HISTORY ─────────────────
  it('returns 409 PRODUCT_HAS_HISTORY when the product has sale items', async () => {
    mocks.prisma.saleItem.count.mockResolvedValue(3);

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const body = (await res.json()) as {
      error: { code: string; details: { counts: { saleItems: number; purchaseItems: number; refundItems: number } } };
    };

    expect(res.status).toBe(409);
    expect(body.error.code).toBe('PRODUCT_HAS_HISTORY');
    expect(body.error.details.counts.saleItems).toBe(3);
    expect(body.error.details.counts.purchaseItems).toBe(0);
    expect(body.error.details.counts.refundItems).toBe(0);
    // No delete attempted
    expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
  });

  // ── 3. Wrong businessId → 404 ─────────────────────────────────────────────
  it('returns 404 when the product belongs to a different business', async () => {
    mocks.prisma.product.findFirst.mockResolvedValue(null);

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const body = (await res.json()) as { error: { code: string } };

    expect(res.status).toBe(404);
    expect(body.error.code).toBe('NOT_FOUND');
    expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
  });

  // ── 4. CASHIER role → 403 ─────────────────────────────────────────────────
  it('returns 403 for CASHIER role', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ownerId,
      fullName: 'Test Cashier',
      role: 'CASHIER',
      active: true,
      mustChangePin: false,
    });

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });

    expect(res.status).toBe(403);
    expect(mocks.prisma.product.findFirst).not.toHaveBeenCalled();
  });

  // ── 5. STOCK_CLERK role → 403 ─────────────────────────────────────────────
  it('returns 403 for STOCK_CLERK role', async () => {
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ownerId,
      fullName: 'Stock Clerk',
      role: 'STOCK_CLERK',
      active: true,
      mustChangePin: false,
    });

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });

    expect(res.status).toBe(403);
    expect(mocks.prisma.product.findFirst).not.toHaveBeenCalled();
  });

  // ── 6. Opening-stock movements removed in transaction ─────────────────────
  it('removes stock movements in the transaction with correct productId', async () => {
    await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });

    expect(mocks.tx.stockMovement.deleteMany).toHaveBeenCalledWith({
      where: { productId },
    });
    // SET LOCAL call must come before deleteMany
    const queryRawOrder = mocks.tx.$queryRaw.mock.invocationCallOrder[1]!;
    const deleteManyOrder = mocks.tx.stockMovement.deleteMany.mock.invocationCallOrder[0]!;
    expect(queryRawOrder).toBeLessThan(deleteManyOrder);
  });

  // ── 7. Audit log beforeJson is correct ────────────────────────────────────
  it('writes audit log with correct beforeJson for a zero-stock product', async () => {
    mocks.prisma.product.findFirst.mockResolvedValue(
      makeProduct({ name: 'Test', sku: 'T-001', stock: { toString: () => '0' } }),
    );

    await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });

    const auditCall = mocks.tx.auditLog.create.mock.calls[0]?.[0];
    expect(auditCall?.data.action).toBe('PRODUCT_PURGE');
    expect(auditCall?.data.beforeJson.name).toBe('Test');
    expect(auditCall?.data.beforeJson.discardedQty).toBe('0');
  });

  // ── 8. Non-zero stock without discardStock → 422 ──────────────────────────
  it('returns 422 NON_ZERO_STOCK when product has stock and discardStock is not set', async () => {
    mocks.prisma.product.findFirst.mockResolvedValue(
      makeProduct({ stock: { toString: () => '5' } }),
    );
    // Number(stock) must be > 0; override stock as a Decimal-like
    // The test product above has toString()=>'5' which Number() will return NaN for.
    // We need a value where Number(existing.stock) > 0.
    mocks.prisma.product.findFirst.mockResolvedValue({
      ...makeProduct(),
      stock: 5,
    });

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: authHeaders(),
    });
    const body = (await res.json()) as { error: { code: string; details: { stock: number } } };

    expect(res.status).toBe(422);
    expect(body.error.code).toBe('NON_ZERO_STOCK');
    expect(body.error.details.stock).toBe(5);
    expect(mocks.prisma.$transaction).not.toHaveBeenCalled();
  });

  // ── 9. Non-zero stock with discardStock:true → 200, discardedQty in audit ─
  it('succeeds with discardStock:true and records discardedQty in the audit log', async () => {
    mocks.prisma.product.findFirst.mockResolvedValue({
      ...makeProduct(),
      stock: 5,
    });

    const res = await fetch(`${baseUrl}/products/${productId}`, {
      method: 'DELETE',
      headers: { ...authHeaders(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ discardStock: true }),
    });

    expect(res.status).toBe(200);
    const auditCall = mocks.tx.auditLog.create.mock.calls[0]?.[0];
    // stock is 5 (number); discardedQty should be '5' or 5 (the stock value)
    expect(Number(auditCall?.data.beforeJson.discardedQty)).toBe(5);
  });

  // ── 10. Archive route → 200 { active: false }, idempotent ─────────────────
  it('POST /archive sets active=false and is idempotent', async () => {
    // First call: product is active
    mocks.prisma.product.findFirst.mockResolvedValue(makeProduct({ active: true }));
    mocks.prisma.product.update.mockResolvedValue({ id: productId, active: false });

    const res1 = await fetch(`${baseUrl}/products/${productId}/archive`, {
      method: 'POST',
      headers: authHeaders(),
    });
    const body1 = (await res1.json()) as { id: string; active: boolean };

    expect(res1.status).toBe(200);
    expect(body1).toEqual({ id: productId, active: false });
    expect(mocks.prisma.product.update).toHaveBeenCalledWith({
      where: { id: productId },
      data: { active: false },
    });

    // Second call: product is already inactive — update must NOT be called again
    vi.clearAllMocks();
    mocks.prisma.user.findUnique.mockResolvedValue({
      id: ownerId, fullName: 'Test Owner', role: 'OWNER', active: true, mustChangePin: false,
    });
    mocks.prisma.product.findFirst.mockResolvedValue(makeProduct({ active: false }));

    const res2 = await fetch(`${baseUrl}/products/${productId}/archive`, {
      method: 'POST',
      headers: authHeaders(),
    });
    const body2 = (await res2.json()) as { id: string; active: boolean };

    expect(res2.status).toBe(200);
    expect(body2).toEqual({ id: productId, active: false });
    expect(mocks.prisma.product.update).not.toHaveBeenCalled();
  });
});
