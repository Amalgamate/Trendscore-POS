/**
 * Customers module — credit accounts and ledger management.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const ListQuerySchema = z.object({
  search: z.string().optional(),
  status: z.enum(['ACTIVE', 'ARCHIVED']).optional().default('ACTIVE'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(200).default(100),
});

const CreateCustomerSchema = z.object({
  fullName: z.string().min(1).max(200),
  phone: z.string().optional(),
  email: z.string().email().optional(),
  address: z.string().optional(),
  creditLimit: z.number().nonnegative().default(0),
  notes: z.string().optional(),
});

const UpdateCustomerSchema = CreateCustomerSchema.partial().extend({
  creditFrozen: z.boolean().optional(),
});
const UpdateNotesSchema = z.object({
  notes: z.string().max(10_000).nullable(),
});

const UploadDocumentSchema = z.object({
  fileName: z.string().min(1).max(255),
  contentType: z.enum(['application/pdf', 'image/jpeg', 'image/png']),
  contentBase64: z.string().min(4).max(11_184_812),
});

const CUSTOMER_DOCUMENT_MAX_BYTES = 8 * 1024 * 1024;

const RecordPaymentSchema = z.object({
  amount: z.number().positive(),
  reference: z.string().min(1),
  method: z.enum(['CASH', 'MPESA', 'BANK']),
  note: z.string().optional(),
});

export function customersRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /customers
  router.get('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    const query = parseQuery(ListQuerySchema, req, res);
    if (!query) return;

    const page = query.page ?? 1;
    const limit = query.limit ?? 100;

    const where = {
      businessId,
      status: query.status,
      ...(query.search
        ? {
            OR: [
              { fullName: { contains: query.search, mode: 'insensitive' as const } },
              { phone: { contains: query.search } },
            ],
          }
        : {}),
    };

    try {
      const [customers, total] = await Promise.all([
        prisma.customer.findMany({
          where,
          orderBy: { fullName: 'asc' },
          skip: (page - 1) * limit,
          take: limit,
        }),
        prisma.customer.count({ where }),
      ]);

      return send200(res, {
        data: customers.map(mapCustomer),
        meta: { total, page, limit },
      });
    } catch (err) {
      console.error('customers/list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch customers.');
    }
  });

  // GET /customers/:id
  router.get('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId },
        include: {
          ledger: {
            orderBy: { createdAt: 'desc' },
            take: 50,
          },
        },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      return send200(res, {
        ...mapCustomer(customer),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ledger: (customer as any).ledger?.map(mapLedgerEntry) ?? [],
      });
    } catch (err) {
      console.error('customers/get error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch customer.');
    }
  });

  // POST /customers
  router.post('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(CreateCustomerSchema, req, res);
    if (!body) return;

    try {
      const customer = await prisma.customer.create({
        data: { businessId, ...body },
      });
      return send201(res, mapCustomer(customer));
    } catch (err: unknown) {
      console.error('customers/create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create customer.');
    }
  });

  // DELETE /customers/:id — only allowed when balance is zero
  router.delete('/:id', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      if (Number(customer.balance) !== 0) {
        return sendError(res, 409, 'BALANCE_NOT_ZERO', 'Cannot delete a customer with an outstanding balance. Clear the debt first.');
      }
      await prisma.customer.delete({ where: { id: req.params.id } });
      return send200(res, { ok: true });
    } catch (err: unknown) {
      console.error('customers/delete error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to delete customer.');
    }
  });

  // PATCH /customers/:id
  router.patch('/:id', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    const body = parseBody(UpdateCustomerSchema, req, res);
    if (!body) return;

    try {
      const result = await prisma.customer.updateMany({
        where: { id: req.params.id, businessId },
        data: body,
      });
      if (result.count === 0) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      const customer = await prisma.customer.findFirstOrThrow({
        where: { id: req.params.id, businessId },
      });
      return send200(res, mapCustomer(customer));
    } catch (err: unknown) {
      console.error('customers/update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update customer.');
    }
  });

  router.patch('/:id/notes', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(UpdateNotesSchema, req, res);
    if (!body) return;
    try {
      const result = await prisma.customer.updateMany({
        where: { id: req.params.id, businessId },
        data: { notes: body.notes },
      });
      if (result.count === 0) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      const customer = await prisma.customer.findFirstOrThrow({
        where: { id: req.params.id, businessId },
      });
      return send200(res, mapCustomer(customer));
    } catch (err) {
      console.error('customers/notes error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to save customer notes.');
    }
  });

  router.post('/:id/restore', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const result = await prisma.customer.updateMany({
        where: { id: req.params.id, businessId, status: 'ARCHIVED' },
        data: { status: 'ACTIVE' },
      });
      if (result.count === 0) {
        const customer = await prisma.customer.findFirst({
          where: { id: req.params.id, businessId },
          select: { status: true },
        });
        if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
        return sendError(res, 409, 'NOT_ARCHIVED', 'Customer account is already active.');
      }
      const restored = await prisma.customer.findFirstOrThrow({
        where: { id: req.params.id, businessId },
      });
      return send200(res, mapCustomer(restored));
    } catch (err) {
      console.error('customers/restore error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to restore customer.');
    }
  });

  router.delete('/:id/permanent', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId, status: 'ARCHIVED' },
        include: {
          _count: { select: { ledger: true, sales: true, payments: true, documents: true } },
        },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Archived customer not found.');
      if (Number(customer.balance) > 0) {
        return sendError(res, 409, 'OUTSTANDING_BALANCE', 'Settle the customer balance before deleting this account.');
      }
      if (customer._count.ledger > 0 || customer._count.sales > 0 ||
          customer._count.payments > 0 || customer._count.documents > 0) {
        return sendError(
          res,
          409,
          'CUSTOMER_HISTORY_EXISTS',
          'This account has retained history or documents and cannot be permanently deleted. Keep it archived instead.',
        );
      }
      await prisma.customer.delete({ where: { id: customer.id } });
      return send200(res, { id: customer.id, deleted: true });
    } catch (err) {
      console.error('customers/delete error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to permanently delete customer.');
    }
  });

  router.get('/:id/documents', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      const documents = await prisma.customerDocument.findMany({
        where: { customerId: customer.id },
        orderBy: { createdAt: 'desc' },
        select: { id: true, fileName: true, contentType: true, size: true, createdAt: true },
      });
      return send200(res, documents);
    } catch (err) {
      console.error('customers/documents list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch customer documents.');
    }
  });

  router.post('/:id/documents', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(UploadDocumentSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');

      const data = Buffer.from(body.contentBase64, 'base64');
      if (data.length === 0 || data.length > CUSTOMER_DOCUMENT_MAX_BYTES ||
          data.toString('base64') !== body.contentBase64) {
        return sendError(res, 422, 'INVALID_DOCUMENT', 'Choose a valid file no larger than 8 MB.');
      }
      const document = await prisma.customerDocument.create({
        data: {
          customerId: customer.id,
          fileName: body.fileName.replace(/[\\/\u0000-\u001f]/g, '_'),
          contentType: body.contentType,
          size: data.length,
          data,
          createdById: auth.userId,
        },
        select: { id: true, fileName: true, contentType: true, size: true, createdAt: true },
      });
      return send201(res, document);
    } catch (err) {
      console.error('customers/documents upload error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to upload customer document.');
    }
  });

  router.get('/:id/documents/:documentId', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    try {
      const document = await prisma.customerDocument.findFirst({
        where: {
          id: req.params.documentId,
          customerId: req.params.id,
          customer: { businessId },
        },
      });
      if (!document) return sendError(res, 404, 'NOT_FOUND', 'Customer document not found.');
      res.setHeader('Content-Type', document.contentType);
      res.setHeader('Content-Length', document.size);
      res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(document.fileName)}"`);
      res.setHeader('X-Content-Type-Options', 'nosniff');
      return res.status(200).send(document.data);
    } catch (err) {
      console.error('customers/documents download error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to download customer document.');
    }
  });

  router.delete('/:id/documents/:documentId', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const result = await prisma.customerDocument.deleteMany({
        where: {
          id: req.params.documentId,
          customerId: req.params.id,
          customer: { businessId },
        },
      });
      if (result.count === 0) return sendError(res, 404, 'NOT_FOUND', 'Customer document not found.');
      return send200(res, { id: req.params.documentId, deleted: true });
    } catch (err) {
      console.error('customers/documents delete error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to delete customer document.');
    }
  });

  // Archive customer accounts without removing their append-only financial history.
  router.delete('/:id', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const customer = await prisma.customer.findFirst({
        where: { id: req.params.id, businessId },
      });
      if (!customer) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      if (customer.status === 'ARCHIVED') {
        return sendError(
          res,
          409,
          'ALREADY_ARCHIVED',
          'Customer account is already archived.',
        );
      }

      const result = await prisma.customer.updateMany({
        where: {
          id: customer.id,
          businessId,
          status: 'ACTIVE',
          balance: { lte: 0 },
        },
        data: { status: 'ARCHIVED' },
      });
      if (result.count === 0) {
        const current = await prisma.customer.findFirst({
          where: { id: customer.id, businessId },
        });
        if (!current) return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
        if (current.status === 'ARCHIVED') {
          return sendError(
            res,
            409,
            'ALREADY_ARCHIVED',
            'Customer account is already archived.',
          );
        }
        return sendError(
          res,
          409,
          'OUTSTANDING_BALANCE',
          'Settle the customer balance before archiving this account.',
        );
      }

      const archived = await prisma.customer.findFirstOrThrow({
        where: { id: customer.id, businessId },
      });
      return send200(res, mapCustomer(archived));
    } catch (err) {
      console.error('customers/archive error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to archive customer.');
    }
  });

  // POST /customers/:id/payments
  router.post('/:id/payments', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(RecordPaymentSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    const customerId = req.params.id;
    if (!customerId) return sendError(res, 400, 'BAD_REQUEST', 'Missing customer ID.');

    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw`
          SELECT "id" FROM "customers"
          WHERE "id" = ${customerId}::uuid AND "businessId" = ${businessId}::uuid
          FOR UPDATE
        `;
        const customer = await tx.customer.findFirst({
          where: { id: customerId, businessId },
        });
        if (!customer) throw new Error('CUSTOMER_NOT_FOUND');
        if (body.amount > Number(customer.balance)) {
          throw new Error('PAYMENT_EXCEEDS_BALANCE');
        }
        const newBalance = Math.max(0, Number(customer.balance) - body.amount);

        await tx.customer.update({
          where: { id: customerId },
          data: { balance: newBalance },
        });

        const entry = await tx.customerLedger.create({
          data: {
            customerId,
            businessId,
            entryType: 'CREDIT',
            amount: body.amount,
            balance: newBalance,
            entityType: 'CUSTOMER_PAYMENT',
            reference: body.reference,
            note: body.note ?? `Payment via ${body.method}`,
            createdById: auth.userId,
          },
        });

        await tx.customerPayment.create({
          data: {
            customerId,
            businessId,
            amount: body.amount,
            method: body.method,
            reference: body.reference,
            receivedById: auth.userId,
          },
        });

        return { payment: entry, newBalance };
      });

      return send201(res, result);
    } catch (err) {
      if (err instanceof Error && err.message === 'CUSTOMER_NOT_FOUND') {
        return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      }
      if (err instanceof Error && err.message === 'PAYMENT_EXCEEDS_BALANCE') {
        return sendError(res, 409, 'PAYMENT_EXCEEDS_BALANCE', 'Payment cannot exceed the current outstanding balance.');
      }
      console.error('customers/payment error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to record payment.');
    }
  });

  // GET /customers/:id/ledger
  router.get('/:id/ledger', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK'), async (req, res) => {
    try {
      const entries = await prisma.customerLedger.findMany({
        where: { customerId: req.params.id, customer: { businessId } },
        orderBy: { createdAt: 'desc' },
        take: 100,
      });
      return send200(res, entries.map(mapLedgerEntry));
    } catch (err) {
      console.error('customers/ledger error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch ledger.');
    }
  });

  return router;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapCustomer(c: any) {
  return {
    id: c.id,
    fullName: c.fullName,
    phone: c.phone,
    email: c.email,
    address: c.address,
    creditLimit: Number(c.creditLimit),
    balance: Number(c.balance),
    status: c.status,
    creditFrozen: c.creditFrozen,
    notes: c.notes,
    createdAt: c.createdAt,
    updatedAt: c.updatedAt,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapLedgerEntry(e: any) {
  return {
    id: e.id,
    entryType: e.entryType,
    amount: Number(e.amount),
    balance: Number(e.balance),
    reference: e.reference,
    note: e.note,
    createdAt: e.createdAt,
  };
}
