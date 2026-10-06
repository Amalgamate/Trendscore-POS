/**
 * Sales module — create, list, and reverse completed sales.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import type { SaleStatus, PaymentMethod } from '@prisma/client';
import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth } from '../../lib/auth.middleware';
import { SaleValidationError } from './pricing';
import { createSale, DuplicateSaleError } from './create-sale';

const ListSalesQuerySchema = z.object({
  method: z.enum(['CASH', 'MPESA', 'CREDIT', 'BANK']).optional(),
  status: z.enum(['DRAFT', 'COMPLETED', 'PARTIALLY_REFUNDED', 'REFUNDED', 'VOIDED']).optional(),
  customerId: z.string().uuid().optional(),
  dateFrom: z.string().optional(),
  dateTo: z.string().optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(200).default(50),
});

const CreateSaleBodySchema = z.object({
  idempotencyKey: z.string().min(1),
  clientRef: z.string().optional().default(''),
  method: z.enum(['CASH', 'MPESA', 'CREDIT', 'BANK']),
  customerId: z.string().uuid().optional(),
  offline: z.boolean().optional().default(false),
  lines: z.array(
    z.object({
      productId: z.string().uuid(),
      quantity: z.number().positive(),
    }),
  ).min(1, 'A sale must have at least one line.'),
  cashTendered: z.number().optional(),
});

const ReversalBodySchema = z.object({
  reason: z.string().min(1),
});

export function salesRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /sales
  router.get('/', requireAuth, async (req, res) => {
    const query = parseQuery(ListSalesQuerySchema, req, res);
    if (!query) return;

    const page = query.page ?? 1;
    const limit = query.limit ?? 50;

    const where: Prisma.SaleWhereInput = {
      businessId,
      ...(query.method ? { payments: { some: { method: query.method as PaymentMethod } } } : {}),
      ...(query.status ? { status: query.status as SaleStatus } : {}),
      ...(query.customerId ? { customerId: query.customerId } : {}),
      ...(query.dateFrom || query.dateTo
        ? {
            createdAt: {
              ...(query.dateFrom ? { gte: new Date(query.dateFrom) } : {}),
              ...(query.dateTo ? { lte: new Date(query.dateTo) } : {}),
            },
          }
        : {}),
    };

    try {
      const [sales, total] = await Promise.all([
        prisma.sale.findMany({
          where,
          include: {
            items: { include: { product: { select: { name: true, sku: true } } } },
            payments: true,
            customer: { select: { fullName: true, phone: true } },
            cashier: { select: { fullName: true } },
          },
          orderBy: { createdAt: 'desc' },
          skip: (page - 1) * limit,
          take: limit,
        }),
        prisma.sale.count({ where }),
      ]);

      return send200(res, {
        data: sales.map(mapSale),
        meta: { total, page, limit },
      });
    } catch (err) {
      console.error('sales/list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch sales.');
    }
  });

  // GET /sales/summary
  router.get('/summary', requireAuth, async (req, res) => {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    try {
      const [dayResult, dayCount] = await Promise.all([
        prisma.sale.aggregate({
          where: { businessId, status: 'COMPLETED', createdAt: { gte: today, lt: tomorrow } },
          _sum: { total: true },
          _count: true,
        }),
        prisma.sale.count({ where: { businessId, status: 'COMPLETED', createdAt: { gte: today, lt: tomorrow } } }),
      ]);

      const sevenDaysAgo = new Date(today);
      sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

      const recentSales = await prisma.sale.findMany({
        where: { businessId, status: 'COMPLETED', createdAt: { gte: sevenDaysAgo } },
        select: { total: true, createdAt: true, payments: { select: { method: true, amount: true } } },
      });

      const byMethod: Record<string, number> = {};
      for (const s of recentSales) {
        for (const p of s.payments) {
          byMethod[p.method] = (byMethod[p.method] ?? 0) + Number(p.amount);
        }
      }

      return send200(res, {
        today: {
          total: Number(dayResult._sum.total ?? 0),
          count: dayCount,
        },
        last7Days: {
          total: recentSales.reduce((sum, s) => sum + Number(s.total), 0),
          count: recentSales.length,
          byMethod,
        },
      });
    } catch (err) {
      console.error('sales/summary error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch summary.');
    }
  });

  // GET /sales/:id
  router.get('/:id', requireAuth, async (req, res) => {
    try {
      const sale = await prisma.sale.findFirst({
        where: { id: req.params.id, businessId },
        include: {
          items: { include: { product: { select: { name: true, sku: true } } } },
          payments: true,
          customer: { select: { fullName: true, phone: true } },
          cashier: { select: { fullName: true } },
        },
      });
      if (!sale) return sendError(res, 404, 'NOT_FOUND', 'Sale not found.');
      return send200(res, mapSale(sale));
    } catch (err) {
      console.error('sales/get error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch sale.');
    }
  });

  // POST /sales
  router.post('/', requireAuth, async (req, res) => {
    const body = parseBody(CreateSaleBodySchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    try {
      const result = await createSale(prisma, {
        businessId,
        cashierId: auth.userId,
        idempotencyKey: body.idempotencyKey,
        clientRef: body.clientRef,
        customerId: body.customerId,
        method: body.method as PaymentMethod,
        offline: body.offline,
        lines: body.lines,
      });

      return send201(res, result);
    } catch (err) {
      if (err instanceof SaleValidationError) {
        return sendError(res, 422, 'VALIDATION_ERROR', err.message);
      }
      if (err instanceof DuplicateSaleError) {
        return sendError(res, 409, 'DUPLICATE_SALE', err.message, { receiptNumber: err.receiptNumber });
      }
      console.error('sales/create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create sale.');
    }
  });

  // POST /sales/:id/reverse
  router.post('/:id/reverse', requireAuth, async (req, res) => {
    const body = parseBody(ReversalBodySchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    try {
      const result = await prisma.$transaction(async (tx) => {
        const sale = await tx.sale.findFirstOrThrow({
          where: { id: req.params.id, businessId },
          include: { items: true, payments: true, customer: true },
        });

        if (sale.status === 'REFUNDED' || sale.status === 'VOIDED') {
          throw new Error('ALREADY_REVERSED');
        }

        // 1. Mark as refunded
        await tx.sale.update({
          where: { id: req.params.id },
          data: { status: 'REFUNDED' },
        });

        // 2. Restore stock — append only
        for (const item of sale.items) {
          const product = await tx.product.update({
            where: { id: item.productId },
            data: { stock: { increment: Number(item.quantity) } },
          });
          await tx.stockMovement.create({
            data: {
              businessId,
              productId: item.productId,
              createdById: auth.userId,
              type: 'RETURN_FROM_CUSTOMER',
              quantity: Number(item.quantity),
              balanceAfter: Number(product.stock),
              note: `Reversal: ${sale.receiptNumber} — ${body.reason}`,
              saleId: sale.id,
            },
          });
        }

        // 3. If credit sale, reduce customer balance via ledger append
        if (sale.customerId && sale.customer) {
          const newBalance = Math.max(0, Number(sale.customer.balance) - Number(sale.total));
          await tx.customer.update({ where: { id: sale.customerId }, data: { balance: newBalance } });
          await tx.customerLedger.create({
            data: {
              customerId: sale.customerId,
              businessId,
              entryType: 'CREDIT',
              amount: Number(sale.total),
              balance: newBalance,
              entityType: 'SALE',
              entityId: sale.id,
              reference: `REVERSAL:${sale.receiptNumber}`,
              note: body.reason,
              createdById: auth.userId,
            },
          });
        }

        return { saleId: sale.id, receiptNumber: sale.receiptNumber };
      });

      return send200(res, { reversed: true, ...result });
    } catch (err) {
      if (err instanceof Error && err.message === 'ALREADY_REVERSED') {
        return sendError(res, 409, 'ALREADY_REVERSED', 'Sale has already been reversed.');
      }
      console.error('sales/reverse error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to reverse sale.');
    }
  });

  return router;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapSale(s: any) {
  return {
    id: s.id,
    receiptNumber: s.receiptNumber,
    status: s.status,
    subtotal: Number(s.subtotal),
    vatAmount: Number(s.vatAmount),
    total: Number(s.total),
    cashier: s.cashier,
    customer: s.customer,
    items: s.items?.map((i: any) => ({
      productId: i.productId,
      productName: i.product?.name ?? i.productId,
      sku: i.product?.sku,
      quantity: Number(i.quantity),
      unitPrice: Number(i.unitPrice),
      lineTotal: Number(i.lineTotal),
    })),
    payments: s.payments?.map((p: any) => ({
      method: p.method,
      amount: Number(p.amount),
      reference: p.idempotencyKey,
    })),
    createdAt: s.createdAt,
  };
}
