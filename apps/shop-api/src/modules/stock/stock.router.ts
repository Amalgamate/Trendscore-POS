import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';
import { toBaseQuantity, UnitConversionError } from '../sales/measured-units';

const HistoryQuery = z.object({
  productId: z.string().uuid().optional(),
  type: z.enum(['PURCHASE', 'SALE', 'STOREFRONT_RESERVATION', 'STOREFRONT_RELEASE', 'RETURN_TO_SUPPLIER', 'ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'DAMAGE', 'EXPIRY', 'RETURN_FROM_CUSTOMER', 'TRANSFER_IN', 'TRANSFER_OUT', 'VARIANCE']).optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

const CountBody = z.object({
  productId: z.string().uuid(),
  countedQuantity: z.number().finite().nonnegative(),
  reason: z.string().trim().min(1).max(500).default('CORRECTION'),
});

const ReceiveBody = z.object({
  supplierId: z.string().uuid().optional(),
  reference: z.string().trim().max(100).optional(),
  invoiceNumber: z.string().trim().max(100).optional(),
  items: z.array(z.object({
    productId: z.string().uuid(),
    quantity: z.number().positive(),
    unit: z.string().min(1).max(16),
    unitCost: z.number().nonnegative(),
  })).min(1).max(100),
});

export function stockRouter(businessId: string): Router {
  const router = ExpressRouter();

  router.get('/movements', requireAuth, requireRole('SUPER_ADMIN', 'OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const query = parseQuery(HistoryQuery, req, res);
    if (!query) return;
    if (query.from && query.to && new Date(query.from) >= new Date(query.to)) {
      return sendError(res, 422, 'INVALID_DATE_RANGE', '`from` must be earlier than `to`.');
    }
    try {
      const where = {
        businessId,
        ...(query.productId ? { productId: query.productId } : {}),
        ...(query.type ? { type: query.type } : {}),
        ...(query.from || query.to ? { createdAt: { ...(query.from ? { gte: new Date(query.from) } : {}), ...(query.to ? { lt: new Date(query.to) } : {}) } } : {}),
      };
      const [rows, total] = await Promise.all([
        prisma.stockMovement.findMany({
          where,
          include: { product: { select: { id: true, name: true, sku: true, unit: true } }, createdBy: { select: { id: true, fullName: true } } },
          orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
          skip: ((query.page ?? 1) - 1) * (query.limit ?? 50),
          take: query.limit ?? 50,
        }),
        prisma.stockMovement.count({ where }),
      ]);
      return send200(res, {
        items: rows.map((row) => ({
          id: row.id, productId: row.productId, productName: row.product.name,
          sku: row.product.sku, unit: row.product.unit, type: row.type,
          quantity: Number(row.quantity), balanceAfter: Number(row.balanceAfter),
          reason: row.reason, note: row.note, reference: row.reference,
          createdAt: row.createdAt, createdBy: row.createdBy?.fullName ?? null,
        })),
        page: query.page ?? 1, limit: query.limit ?? 50, total,
      });
    } catch (error) {
      console.error('stock/movements error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to load stock movement history.');
    }
  });

  router.post('/count', requireAuth, requireRole('SUPER_ADMIN', 'OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(CountBody, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string };
    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw(Prisma.sql`SELECT "id" FROM "products" WHERE "businessId"=${businessId}::uuid AND "id"=${body.productId}::uuid FOR UPDATE`);
        const product = await tx.product.findFirst({ where: { id: body.productId, businessId } });
        if (!product) return null;
        const before = new Prisma.Decimal(product.stock.toString());
        const counted = new Prisma.Decimal(body.countedQuantity.toString());
        const delta = counted.minus(before);
        await tx.product.update({ where: { id: product.id }, data: { stock: counted, varianceFlag: false } });
        if (delta.isZero()) {
          await tx.auditLog.create({ data: {
            businessId, userId: auth.userId, action: 'STOCK_COUNT_CONFIRMED',
            entityType: 'PRODUCT', entityId: product.id,
            beforeJson: { stock: before.toString(), varianceFlag: product.varianceFlag },
            afterJson: { stock: counted.toString(), varianceFlag: false, reason: body.reason },
          } });
          return { productId: product.id, previousQuantity: before.toNumber(), countedQuantity: counted.toNumber(), delta: 0, movementId: null };
        }
        const movement = await tx.stockMovement.create({
          data: {
            businessId, productId: product.id, createdById: auth.userId,
            type: delta.isPositive() ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
            quantity: delta, balanceAfter: counted, reason: 'CORRECTION',
            note: body.reason,
          },
        });
        await tx.auditLog.create({ data: {
          businessId, userId: auth.userId, action: 'STOCK_COUNT_ADJUSTED',
          entityType: 'PRODUCT', entityId: product.id,
          beforeJson: { stock: before.toString(), varianceFlag: product.varianceFlag }, afterJson: { stock: counted.toString(), varianceFlag: false, reason: body.reason, movementId: movement.id },
        } });
        return { productId: product.id, previousQuantity: before.toNumber(), countedQuantity: counted.toNumber(), delta: delta.toNumber(), movementId: movement.id };
      });
      if (!result) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      return send200(res, result);
    } catch (error) {
      console.error('stock/count error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to record physical stock count.');
    }
  });

  router.post('/receive', requireAuth, requireRole('SUPER_ADMIN', 'OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(ReceiveBody, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string };
    try {
      const result = await prisma.$transaction(async (tx) => {
        const ids = [...new Set(body.items.map((item) => item.productId))].sort();
        await tx.$queryRaw(Prisma.sql`SELECT "id" FROM "products" WHERE "businessId"=${businessId}::uuid AND "id" IN (${Prisma.join(ids.map((id) => Prisma.sql`${id}::uuid`))}) ORDER BY "id" FOR UPDATE`);
        const products = await tx.product.findMany({ where: { id: { in: ids }, businessId } });
        if (products.length !== ids.length) throw new Error('PRODUCT_NOT_FOUND');
        const byId = new Map(products.map((product) => [product.id, product]));
        const lines = body.items.map((item) => {
          const product = byId.get(item.productId)!;
          const milli = toBaseQuantity(item.quantity, item.unit, product.unit);
          return { item, product, quantity: new Prisma.Decimal(milli).dividedBy(1000) };
        });
        const subtotal = lines.reduce((sum, line) => sum.plus(line.quantity.mul(line.item.unitCost)), new Prisma.Decimal(0));
        const purchase = await tx.purchase.create({ data: {
          businessId, supplierId: body.supplierId, reference: body.reference,
          invoiceNumber: body.invoiceNumber, status: 'COMPLETED', subtotal,
          vatAmount: 0, total: subtotal, paid: 0, balance: subtotal,
        } });
        const movements = [];
        for (const line of lines) {
          const before = new Prisma.Decimal(line.product.stock.toString());
          const after = before.plus(line.quantity);
          await tx.product.update({ where: { id: line.product.id }, data: { stock: after, costPrice: line.item.unitCost } });
          const purchaseItem = await tx.purchaseItem.create({ data: {
            purchaseId: purchase.id, productId: line.product.id,
            quantity: line.quantity, unitCost: line.item.unitCost,
            lineTotal: line.quantity.mul(line.item.unitCost),
          } });
          const movement = await tx.stockMovement.create({ data: {
            businessId, productId: line.product.id, type: 'PURCHASE',
            quantity: line.quantity, balanceAfter: after, unitCost: line.item.unitCost,
            reference: body.reference ?? body.invoiceNumber ?? purchase.id,
            note: 'Stock received', purchaseId: purchase.id, createdById: auth.userId,
          } });
          movements.push({ purchaseItemId: purchaseItem.id, movementId: movement.id, productId: line.product.id, quantity: line.quantity.toNumber(), balanceAfter: after.toNumber() });
        }
        await tx.auditLog.create({ data: {
          businessId, userId: auth.userId, action: 'STOCK_PURCHASE_RECEIVED',
          entityType: 'PURCHASE', entityId: purchase.id,
          afterJson: { reference: body.reference ?? null, itemCount: lines.length, movements },
        } });
        return { purchaseId: purchase.id, reference: body.reference ?? body.invoiceNumber ?? null, total: subtotal.toNumber(), movements };
      });
      return send200(res, result);
    } catch (error) {
      if (error instanceof UnitConversionError) return sendError(res, 422, 'INVALID_STOCK_UNIT', error.message);
      if (error instanceof Error && error.message === 'PRODUCT_NOT_FOUND') return sendError(res, 404, 'PRODUCT_NOT_FOUND', 'One or more products were not found.');
      console.error('stock/receive error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to receive stock.');
    }
  });

  return router;
}
