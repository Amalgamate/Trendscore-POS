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
  status: z.string().optional().default('ACTIVE'),
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

const UpdateCustomerSchema = CreateCustomerSchema.partial();

const RecordPaymentSchema = z.object({
  amount: z.number().positive(),
  reference: z.string().min(1),
  method: z.enum(['CASH', 'MPESA', 'BANK']),
  note: z.string().optional(),
});

export function customersRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /customers
  router.get('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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
  router.get('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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
  router.post('/', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
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

  // PATCH /customers/:id
  router.patch('/:id', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    const body = parseBody(UpdateCustomerSchema, req, res);
    if (!body) return;

    try {
      const customer = await prisma.customer.update({
        where: { id: req.params.id },
        data: body,
      });
      return send200(res, mapCustomer(customer));
    } catch (err: unknown) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if ((err as any)?.code === 'P2025') return sendError(res, 404, 'NOT_FOUND', 'Customer not found.');
      console.error('customers/update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update customer.');
    }
  });

  // POST /customers/:id/payments
  router.post('/:id/payments', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
    const body = parseBody(RecordPaymentSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    const customerId = req.params.id;
    if (!customerId) return sendError(res, 400, 'BAD_REQUEST', 'Missing customer ID.');

    try {
      const result = await prisma.$transaction(async (tx) => {
        const customer = await tx.customer.findFirstOrThrow({ where: { id: customerId, businessId } });
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
      console.error('customers/payment error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to record payment.');
    }
  });

  // GET /customers/:id/ledger
  router.get('/:id/ledger', requireAuth, requireRole('OWNER', 'MANAGER', 'CASHIER'), async (req, res) => {
    try {
      const entries = await prisma.customerLedger.findMany({
        where: { customerId: req.params.id },
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
