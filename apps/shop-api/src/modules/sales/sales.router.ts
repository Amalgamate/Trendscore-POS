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
import { requireAuth, requireRole } from '../../lib/auth.middleware';
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
  paymentReference: z.string().trim().max(200).optional(),
  customerId: z.string().uuid().optional(),
  customerName: z.string().trim().max(120).optional(),
  stockOverride: z.object({
    approverId: z.string().uuid(),
    pin: z.string().regex(/^\d{4,6}$/),
  }).optional(),
  offline: z.boolean().optional().default(false),
  lines: z.array(
    z.object({
      productId: z.string().uuid(),
      quantity: z.number().positive(),
      unit: z.string().trim().min(1).max(24).optional(),
    }),
  ).min(1, 'A sale must have at least one line.'),
  cashTendered: z.number().nonnegative().optional(),
});

const ReversalBodySchema = z.object({
  reason: z.string().min(1),
});

const ReconcilePaymentBodySchema = z.object({
  mpesaReceipt: z.string().trim().min(3).max(64),
  note: z.string().trim().max(240).optional(),
});

const SalesSummaryQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export function businessDateRange(date: string, timeZone: string): { start: Date; end: Date } {
  const [year, month, day] = date.split('-').map(Number) as [number, number, number];
  const calendarDate = new Date(Date.UTC(year, month - 1, day));
  if (Number.isNaN(calendarDate.getTime()) || calendarDate.toISOString().slice(0, 10) !== date) {
    throw new Error('INVALID_BUSINESS_DATE');
  }

  const utcForLocalMidnight = (value: Date) => {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23',
    }).formatToParts(value);
    const values = Object.fromEntries(parts.map((part) => [part.type, Number(part.value)]));
    const representedAsUtc = Date.UTC(
      values.year!, values.month! - 1, values.day!,
      values.hour!, values.minute!, values.second!,
    );
    return new Date(value.getTime() - (representedAsUtc - Date.UTC(
      value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate(),
      value.getUTCHours(), value.getUTCMinutes(), value.getUTCSeconds(),
    )));
  };

  const localMidnight = new Date(Date.UTC(year, month - 1, day));
  const nextMidnight = new Date(Date.UTC(year, month - 1, day + 1));
  return { start: utcForLocalMidnight(localMidnight), end: utcForLocalMidnight(nextMidnight) };
}

export function salesRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /sales
  router.get('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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

  // GET /sales/summary — business day is midnight to midnight Africa/Nairobi.
  router.get('/summary', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
    const query = parseQuery(SalesSummaryQuerySchema, req, res);
    if (!query) return;
    const auth = res.locals.auth as { userId: string; role: string };
    const date = query.date ?? new Intl.DateTimeFormat('en-CA', {
      timeZone: 'Africa/Nairobi', year: 'numeric', month: '2-digit', day: '2-digit',
    }).format(new Date());
    try {
      const timezoneSetting = await prisma.businessSetting.findUnique({
        where: { businessId_key: { businessId, key: 'timezone' } },
        select: { value: true },
      });
      const timezoneValue = timezoneSetting?.value;
      const timezone = typeof timezoneValue === 'string' ? timezoneValue : 'Africa/Nairobi';
      let range: { start: Date; end: Date };
      try {
        range = businessDateRange(date, timezone);
      } catch {
        return sendError(res, 422, 'VALIDATION_ERROR', 'Date must be a valid YYYY-MM-DD business date or configured timezone.');
      }
      const { start, end } = range;
      const dayWhere: Prisma.SaleWhereInput = {
        businessId,
        status: { in: ['COMPLETED', 'PARTIALLY_REFUNDED'] },
        createdAt: { gte: start, lt: end },
        ...(auth.role === 'CASHIER' ? { cashierId: auth.userId } : {}),
      };
      const [dayResult, dayCount, dayPayments, refunds, creditGiven, debtPayments, voidedCount, vatResult] = await Promise.all([
        prisma.sale.aggregate({
          where: dayWhere,
          _sum: { total: true },
          _count: true,
        }),
        prisma.sale.count({ where: dayWhere }),
        prisma.salePayment.findMany({
          where: { sale: dayWhere, status: 'SUCCESS' },
          select: { method: true, amount: true },
        }),
        prisma.refund.findMany({
          where: {
            businessId,
            createdAt: { gte: start, lt: end },
            ...(auth.role === 'CASHIER' ? { sale: { cashierId: auth.userId } } : {}),
          },
          select: { amount: true },
        }),
        prisma.sale.aggregate({
          where: { ...dayWhere, payments: { some: { method: 'CREDIT', status: 'SUCCESS' } } },
          _sum: { total: true },
        }),
        prisma.customerPayment.groupBy({
          by: ['method'],
          where: {
            businessId,
            createdAt: { gte: start, lt: end },
            ...(auth.role === 'CASHIER' ? { receivedById: auth.userId } : {}),
          },
          _sum: { amount: true },
          _count: { _all: true },
        }),
        prisma.sale.count({
          where: {
            businessId,
            status: 'VOIDED',
            createdAt: { gte: start, lt: end },
            ...(auth.role === 'CASHIER' ? { cashierId: auth.userId } : {}),
          },
        }),
        prisma.sale.aggregate({
          where: dayWhere,
          _sum: { vatAmount: true },
        }),
      ]);

      const todayByMethod: Record<string, number> = {};
      for (const payment of dayPayments) {
        todayByMethod[payment.method] = (todayByMethod[payment.method] ?? 0) + Number(payment.amount);
      }

      const grossSales = Number(dayResult._sum.total ?? 0);
      const refundTotal = refunds.reduce((sum, refund) => sum + Number(refund.amount), 0);
      const vatTotal = Number(vatResult._sum.vatAmount ?? 0);
      const paymentTotal = Object.values(todayByMethod).reduce((sum, value) => sum + value, 0);
      const debtPaymentTotals = Object.fromEntries(debtPayments.map((payment) => [
        payment.method,
        { amount: Number(payment._sum.amount ?? 0), count: payment._count._all },
      ]));

      return send200(res, {
        today: {
          date,
          timezone,
          total: grossSales,
          count: dayCount,
          average: dayCount === 0 ? 0 : grossSales / dayCount,
          byMethod: todayByMethod,
          paymentTotal,
          vatTotal,
          netSales: grossSales - refundTotal,
          refunds: { total: refundTotal, count: refunds.length },
          voidedCount,
          creditGiven: Number(creditGiven._sum.total ?? 0),
          debtPayments: debtPaymentTotals,
        },
      });
    } catch (err) {
      console.error('sales/summary error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch summary.');
    }
  });

  // GET /sales/:id
  router.get('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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
  router.post('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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
        customerName: body.customerName,
        stockOverride: body.stockOverride,
        method: body.method as PaymentMethod,
        paymentReference: body.paymentReference,
        cashTendered: body.cashTendered,
        offline: body.offline,
        lines: body.lines,
      });

      return send201(res, result);
    } catch (err) {
      if (err instanceof SaleValidationError) {
        return sendError(res, 422, err.rejection.kind, err.message, err.rejection);
      }
      if (err instanceof DuplicateSaleError) {
        return sendError(res, 409, 'DUPLICATE_SALE', err.message, {
          receiptNumber: err.receiptNumber,
          saleId: err.saleId,
          total: err.total,
          customerId: err.customerId,
        });
      }
      console.error('sales/create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create sale.');
    }
  });

  // POST /sales/:id/reconcile-payment
  router.post('/:id/reconcile-payment', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    const body = parseBody(ReconcilePaymentBodySchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    if (!z.string().uuid().safeParse(req.params.id).success) {
      return sendError(res, 404, 'NOT_FOUND', 'Sale not found.');
    }

    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw(
          Prisma.sql`SELECT "id" FROM "sales"
            WHERE "id" = ${req.params.id}::uuid
              AND "businessId" = ${businessId}::uuid
            FOR UPDATE`,
        );
        const sale = await tx.sale.findFirst({
          where: { id: req.params.id, businessId },
          include: { payments: true },
        });
        if (!sale) return { error: 'NOT_FOUND' as const };
        if (sale.status !== 'COMPLETED') {
          return { error: 'SALE_NOT_RECONCILABLE' as const };
        }

        const pending = sale.payments.find(
          (payment) => payment.method === 'MPESA' && payment.status === 'PENDING',
        );
        if (!pending) {
          const alreadyReconciled = sale.payments.find(
            (payment) =>
              payment.method === 'MPESA' &&
              payment.status === 'SUCCESS' &&
              payment.reversalOfId !== null,
          );
          if (alreadyReconciled) {
            return {
              saleId: sale.id,
              receiptNumber: sale.receiptNumber,
              mpesaReceipt: alreadyReconciled.mpesaReceipt,
              alreadyReconciled: true,
            };
          }
          return { error: 'NO_PENDING_MPESA' as const };
        }

        const receiptInUse = await tx.salePayment.findUnique({
          where: { mpesaReceipt: body.mpesaReceipt },
          select: { saleId: true },
        });
        if (receiptInUse) return { error: 'MPESA_RECEIPT_USED' as const };

        const reconciledAt = new Date();
        await tx.salePayment.update({
          where: { id: pending.id },
          data: {
            status: 'REVERSED',
            resultCode: 'MANUAL_RECONCILED',
            resultDesc: `Superseded by manual reconciliation from user ${auth.userId}.`,
          },
        });
        await tx.salePayment.create({
          data: {
            saleId: sale.id,
            method: 'MPESA',
            status: 'SUCCESS',
            amount: pending.amount,
            mpesaReceipt: body.mpesaReceipt,
            reference: [
              pending.reference,
              `M-PESA RECEIPT: ${body.mpesaReceipt}`,
            ]
              .filter(Boolean)
              .join(' · '),
            idempotencyKey: `manual-reconcile-${pending.id}`,
            resultCode: 'MANUAL_RECONCILED',
            resultDesc: body.note ?? 'Manually reconciled against the M-Pesa statement.',
            settledAt: reconciledAt,
            reconciledById: auth.userId,
            reconciledAt,
            reversalOfId: pending.id,
          },
        });
        return {
          saleId: sale.id,
          receiptNumber: sale.receiptNumber,
          mpesaReceipt: body.mpesaReceipt,
          alreadyReconciled: false,
        };
      });

      if ('error' in result) {
        if (result.error === 'NOT_FOUND') {
          return sendError(res, 404, 'NOT_FOUND', 'Sale not found.');
        }
        if (result.error === 'MPESA_RECEIPT_USED') {
          return sendError(res, 409, 'MPESA_RECEIPT_USED', 'This M-Pesa receipt is already linked to another payment.');
        }
        if (result.error === 'SALE_NOT_RECONCILABLE') {
          return sendError(res, 409, 'SALE_NOT_RECONCILABLE', 'Only completed sales can be reconciled.');
        }
        return sendError(res, 409, 'NO_PENDING_MPESA', 'This sale has no pending M-Pesa payment.');
      }
      return send200(res, result);
    } catch (err) {
      if (
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === 'P2002'
      ) {
        return sendError(
          res,
          409,
          'MPESA_RECEIPT_USED',
          'This M-Pesa receipt is already linked to another payment.',
        );
      }
      console.error('sales/reconcile-payment error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to reconcile M-Pesa payment.');
    }
  });

  // POST /sales/:id/reverse
  router.post('/:id/reverse', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    const body = parseBody(ReversalBodySchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw(
          Prisma.sql`SELECT "id" FROM "sales"
            WHERE "id" = ${req.params.id}::uuid AND "businessId" = ${businessId}::uuid
            FOR UPDATE`,
        );
        const sale = await tx.sale.findFirstOrThrow({
          where: { id: req.params.id, businessId },
          include: {
            items: true,
            payments: true,
            customer: true,
            storefrontOrder: { select: { id: true } },
          },
        });

        if (sale.storefrontOrder) {
          throw new Error('STOREFRONT_ORDER_REQUIRES_REVIEW');
        }
        if (sale.status === 'REFUNDED' || sale.status === 'VOIDED') {
          throw new Error('ALREADY_REVERSED');
        }

        const claimed = await tx.sale.updateMany({
          where: { id: req.params.id, businessId, status: { notIn: ['REFUNDED', 'VOIDED'] } },
          data: { status: 'REFUNDED' },
        });
        if (claimed.count !== 1) throw new Error('ALREADY_REVERSED');

        // 2. Restore stock — append only
        const productIds = [...new Set(sale.items.map((item) => item.productId))].sort();
        await tx.$queryRaw(
          Prisma.sql`SELECT "id" FROM "products"
            WHERE "businessId" = ${businessId}::uuid
              AND "id" IN (${Prisma.join(productIds.map((id) => Prisma.sql`${id}::uuid`))})
            ORDER BY "id" FOR UPDATE`,
        );
        for (const item of sale.items) {
          const product = await tx.product.update({
            where: { id: item.productId },
            data: { stock: { increment: item.quantity } },
          });
          await tx.stockMovement.create({
            data: {
              businessId,
              productId: item.productId,
              createdById: auth.userId,
              type: 'RETURN_FROM_CUSTOMER',
              quantity: item.quantity,
              balanceAfter: product.stock,
              note: `Reversal: ${sale.receiptNumber} — ${body.reason}`,
              saleId: sale.id,
            },
          });
        }

        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'SALE_REVERSED',
            entityType: 'SALE',
            entityId: sale.id,
            beforeJson: { status: sale.status },
            afterJson: { status: 'REFUNDED', reason: body.reason, receiptNumber: sale.receiptNumber },
          },
        });

        // 3. If credit sale, reduce customer balance via ledger append
        if (sale.customerId && sale.customer) {
          await tx.$queryRaw(
            Prisma.sql`SELECT "id" FROM "customers"
              WHERE "id" = ${sale.customerId}::uuid AND "businessId" = ${businessId}::uuid
              FOR UPDATE`,
          );
          const currentCustomer = await tx.customer.findFirst({
            where: { id: sale.customerId, businessId },
            select: { balance: true },
          });
          const newBalance = Math.max(0, Number(currentCustomer?.balance ?? 0) - Number(sale.total));
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
      if (err instanceof Error && err.message === 'STOREFRONT_ORDER_REQUIRES_REVIEW') {
        return sendError(
          res,
          409,
          'STOREFRONT_ORDER_REQUIRES_REVIEW',
          'This sale is linked to an online order. Review the order and payment before reversing it.',
        );
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
    customerName: s.customerName,
    items: s.items?.map((i: any) => ({
      productId: i.productId,
      productName: i.product?.name ?? i.productId,
      sku: i.product?.sku,
      quantity: Number(i.quantity),
      soldQuantity: Number(i.soldQuantity ?? i.quantity),
      soldUnit: i.soldUnit ?? i.product?.unit ?? 'pc',
      baseUnit: i.product?.unit ?? i.soldUnit ?? 'pc',
      unitPrice: Number(i.unitPrice),
      lineTotal: Number(i.lineTotal),
    })),
    payments: s.payments?.map((p: any) => ({
      id: p.id,
      method: p.method,
      status: p.status,
      amount: Number(p.amount),
      cashTendered:
        p.cashTendered === null || p.cashTendered === undefined
          ? null
          : Number(p.cashTendered),
      changeDue:
        p.changeDue === null || p.changeDue === undefined
          ? null
          : Number(p.changeDue),
      reference: p.reference ?? p.mpesaReceipt ?? '',
      mpesaReceipt: p.mpesaReceipt,
      reconciledAt: p.reconciledAt,
    })),
    createdAt: s.createdAt,
  };
}
