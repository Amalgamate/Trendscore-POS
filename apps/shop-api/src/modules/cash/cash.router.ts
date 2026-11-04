/** Server backed till shifts and append-only drawer movements. */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const OpenSessionSchema = z.object({
  openingCash: z.number().nonnegative().max(1_000_000_000),
});

const MovementSchema = z.object({
  type: z.enum(['PAID_IN', 'PAID_OUT', 'DROP_TO_BANK', 'EXPENSE']),
  amount: z.number().positive().max(1_000_000_000),
  reason: z.string().trim().min(2).max(240),
  idempotencyKey: z.string().trim().min(8).max(120),
});

const CloseSessionSchema = z.object({
  countedCash: z.number().nonnegative().max(1_000_000_000),
  varianceReason: z.string().trim().max(500).optional(),
});

const ReconcileSessionSchema = z.object({
  note: z.string().trim().min(3).max(500),
});

const SessionListSchema = z.object({
  status: z.enum(['OPEN', 'CLOSED', 'RECONCILED']).optional(),
  limit: z.coerce.number().int().positive().max(100).default(20),
});

const cashRoles = ['OWNER', 'MANAGER', 'CASHIER'] as const;
const managerRoles = ['OWNER', 'MANAGER'] as const;

function expectedCash(session: {
  openingCash: Prisma.Decimal;
  cashSales: Prisma.Decimal;
  debtPayments: Prisma.Decimal;
  otherIn: Prisma.Decimal;
  cashRefunds: Prisma.Decimal;
  cashExpenses: Prisma.Decimal;
  dropsToBank: Prisma.Decimal;
  otherOut: Prisma.Decimal;
}) {
  return session.openingCash
    .plus(session.cashSales)
    .plus(session.debtPayments)
    .plus(session.otherIn)
    .minus(session.cashRefunds)
    .minus(session.cashExpenses)
    .minus(session.dropsToBank)
    .minus(session.otherOut);
}

// Prisma Decimal fields are returned as Decimal objects. Convert to plain
// numbers at the API boundary so Flutter receives a stable JSON contract.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapSession(session: any) {
  const computedExpected = expectedCash(session);
  const movements = (session.movements ?? []).map((movement: any) => ({
    id: movement.id,
    type: movement.type,
    direction: movement.direction,
    amount: Number(movement.amount),
    reason: movement.reason,
    reference: movement.reference,
    cashier: movement.createdBy?.fullName ?? '',
    createdAt: movement.createdAt,
  }));
  // Cash sales are immutable sale records linked to the shift. Project them
  // into the journal instead of duplicating them in cash_movements.
  for (const sale of session.sales ?? []) {
    movements.push({
      id: `sale-${sale.id}`,
      type: 'SALE_CASH',
      direction: 'CREDIT',
      amount: Number(sale.total),
      reason: `Cash sale ${sale.receiptNumber}`,
      reference: sale.id,
      cashier: sale.cashier?.fullName ?? session.cashier?.fullName ?? '',
      createdAt: sale.createdAt,
    });
  }
  movements.sort((a: { createdAt: Date }, b: { createdAt: Date }) =>
    new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
  );

  return {
    id: session.id,
    status: session.status,
    cashierId: session.cashierId,
    cashier: session.cashier?.fullName ?? '',
    openedAt: session.openedAt,
    closedAt: session.closedAt,
    openingCash: Number(session.openingCash),
    cashSales: Number(session.cashSales),
    cashRefunds: Number(session.cashRefunds),
    debtPayments: Number(session.debtPayments),
    cashExpenses: Number(session.cashExpenses),
    dropsToBank: Number(session.dropsToBank),
    otherIn: Number(session.otherIn),
    otherOut: Number(session.otherOut),
    expectedCash: Number(computedExpected),
    countedCash: session.countedCash == null ? null : Number(session.countedCash),
    variance: session.variance == null ? null : Number(session.variance),
    varianceReason: session.varianceReason,
    movements,
  };
}

const sessionInclude = {
  cashier: { select: { fullName: true } },
  movements: {
    include: { createdBy: { select: { fullName: true } } },
    orderBy: { createdAt: 'desc' as const },
  },
  sales: {
    where: { status: { in: ['COMPLETED', 'PARTIALLY_REFUNDED'] as const } },
    select: {
      id: true,
      receiptNumber: true,
      total: true,
      createdAt: true,
      cashier: { select: { fullName: true } },
    },
  },
} satisfies Prisma.CashSessionInclude;

export function cashRouter(businessId: string): Router {
  const router = ExpressRouter();

  router.get('/sessions/current', requireAuth, requireRole(...cashRoles), async (_req, res) => {
    const auth = res.locals.auth as { userId: string };
    try {
      const session = await prisma.cashSession.findFirst({
        where: { businessId, cashierId: auth.userId, status: 'OPEN' },
        include: sessionInclude,
      }) ?? await prisma.cashSession.findFirst({
        where: { businessId, cashierId: auth.userId },
        orderBy: { openedAt: 'desc' },
        include: sessionInclude,
      });
      return send200(res, { data: session ? mapSession(session) : null });
    } catch (error) {
      console.error('cash/current session error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not load the till session.');
    }
  });

  router.get('/sessions', requireAuth, requireRole(...cashRoles), async (req, res) => {
    const auth = res.locals.auth as { userId: string; role: string };
    const query = parseQuery(SessionListSchema, req, res);
    if (!query) return;
    try {
      const sessions = await prisma.cashSession.findMany({
        where: {
          businessId,
          ...(query.status ? { status: query.status } : {}),
          ...(auth.role === 'CASHIER' ? { cashierId: auth.userId } : {}),
        },
        orderBy: { openedAt: 'desc' },
        take: query.limit,
        include: sessionInclude,
      });
      return send200(res, { data: sessions.map(mapSession) });
    } catch (error) {
      console.error('cash/session history error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not load till history.');
    }
  });

  router.post('/sessions', requireAuth, requireRole(...cashRoles), async (req, res) => {
    const body = parseBody(OpenSessionSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string; name: string };
    try {
      const session = await prisma.$transaction(async (tx) => {
        // Serialize opening attempts for the same cashier; there is no partial
        // unique index on one-open-session-per-cashier in the existing schema.
        await tx.$queryRaw`SELECT "id" FROM "users" WHERE "id" = ${auth.userId}::uuid FOR UPDATE`;
        const open = await tx.cashSession.findFirst({
          where: { businessId, cashierId: auth.userId, status: 'OPEN' },
          select: { id: true },
        });
        if (open) throw new Error('CASH_SESSION_ALREADY_OPEN');

        const created = await tx.cashSession.create({
          data: {
            businessId,
            cashierId: auth.userId,
            openingCash: new Prisma.Decimal(body.openingCash),
            expectedCash: new Prisma.Decimal(body.openingCash),
          },
        });
        await tx.cashMovement.create({
          data: {
            businessId,
            cashSessionId: created.id,
            type: 'PAID_IN',
            direction: 'CREDIT',
            amount: new Prisma.Decimal(body.openingCash),
            reason: 'Opening till float',
            reference: `OPENING:${created.id}`,
            createdById: auth.userId,
          },
        });
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'CASH_SESSION_OPENED',
            entityType: 'CASH_SESSION',
            entityId: created.id,
            afterJson: { openingCash: body.openingCash },
          },
        });
        return created;
      });
      const full = await prisma.cashSession.findUniqueOrThrow({
        where: { id: session.id },
        include: sessionInclude,
      });
      return send201(res, { data: mapSession(full) });
    } catch (error) {
      if (error instanceof Error && error.message === 'CASH_SESSION_ALREADY_OPEN') {
        return sendError(res, 409, 'CASH_SESSION_ALREADY_OPEN', 'This cashier already has an open till shift. Refresh the Till screen.');
      }
      console.error('cash/open session error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not open the till shift.');
    }
  });

  router.post('/sessions/:id/movements', requireAuth, requireRole(...cashRoles), async (req, res) => {
    const body = parseBody(MovementSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string };
    try {
      const movement = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "cash_sessions" WHERE "id" = ${req.params.id}::uuid AND "businessId" = ${businessId}::uuid AND "cashierId" = ${auth.userId}::uuid AND "status" = 'OPEN'::"CashSessionStatus" FOR UPDATE`;
        const session = await tx.cashSession.findFirst({
          where: { id: req.params.id, businessId, cashierId: auth.userId, status: 'OPEN' },
        });
        if (!session) throw new Error('CASH_SESSION_NOT_OPEN');
        const existing = await tx.cashMovement.findFirst({
          where: { cashSessionId: session.id, reference: body.idempotencyKey },
          include: { createdBy: { select: { fullName: true } } },
        });
        if (existing) return existing;

        const direction = body.type === 'PAID_IN' ? 'CREDIT' : 'DEBIT';
        const amount = new Prisma.Decimal(body.amount);
        const created = await tx.cashMovement.create({
          data: {
            businessId,
            cashSessionId: session.id,
            type: body.type,
            direction,
            amount,
            reason: body.reason,
            reference: body.idempotencyKey,
            createdById: auth.userId,
          },
          include: { createdBy: { select: { fullName: true } } },
        });
        const aggregate = body.type === 'PAID_IN'
          ? { otherIn: { increment: amount } }
          : body.type === 'EXPENSE'
            ? { cashExpenses: { increment: amount } }
            : body.type === 'DROP_TO_BANK'
              ? { dropsToBank: { increment: amount } }
              : { otherOut: { increment: amount } };
        await tx.cashSession.update({ where: { id: session.id }, data: aggregate });
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: `CASH_${body.type}`,
            entityType: 'CASH_SESSION',
            entityId: session.id,
            afterJson: { amount: body.amount, reason: body.reason, movementId: created.id },
          },
        });
        return created;
      });
      return send201(res, {
        data: {
          id: movement.id,
          type: movement.type,
          direction: movement.direction,
          amount: Number(movement.amount),
          reason: movement.reason,
          reference: movement.reference,
          cashier: movement.createdBy.fullName,
          createdAt: movement.createdAt,
        },
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'CASH_SESSION_NOT_OPEN') {
        return sendError(res, 409, 'CASH_SESSION_NOT_OPEN', 'Open a till shift before recording cash movements.');
      }
      console.error('cash/movement error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not record the cash movement.');
    }
  });

  router.post('/sessions/:id/close', requireAuth, requireRole(...cashRoles), async (req, res) => {
    const body = parseBody(CloseSessionSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string };
    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT "id" FROM "cash_sessions" WHERE "id" = ${req.params.id}::uuid AND "businessId" = ${businessId}::uuid AND "cashierId" = ${auth.userId}::uuid FOR UPDATE`;
        const session = await tx.cashSession.findFirst({
          where: { id: req.params.id, businessId, cashierId: auth.userId, status: 'OPEN' },
        });
        if (!session) throw new Error('CASH_SESSION_NOT_OPEN');
        const expected = expectedCash(session);
        const counted = new Prisma.Decimal(body.countedCash);
        const variance = counted.minus(expected);
        if (!variance.isZero() && !body.varianceReason?.trim()) {
          throw new Error('CASH_VARIANCE_REASON_REQUIRED');
        }
        const updated = await tx.cashSession.update({
          where: { id: session.id },
          data: {
            status: 'CLOSED',
            closedAt: new Date(),
            expectedCash: expected,
            countedCash: counted,
            variance,
            varianceReason: body.varianceReason?.trim() || null,
          },
        });
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'CASH_SESSION_CLOSED',
            entityType: 'CASH_SESSION',
            entityId: session.id,
            beforeJson: { status: session.status },
            afterJson: {
              countedCash: body.countedCash,
              expectedCash: Number(expected),
              variance: Number(variance),
              varianceReason: body.varianceReason?.trim() ?? null,
            },
          },
        });
        return updated;
      });
      const full = await prisma.cashSession.findUniqueOrThrow({
        where: { id: result.id },
        include: sessionInclude,
      });
      return send200(res, { data: mapSession(full) });
    } catch (error) {
      if (error instanceof Error && error.message === 'CASH_SESSION_NOT_OPEN') {
        return sendError(res, 409, 'CASH_SESSION_NOT_OPEN', 'This till shift is already closed or not yours.');
      }
      if (error instanceof Error && error.message === 'CASH_VARIANCE_REASON_REQUIRED') {
        return sendError(res, 422, 'CASH_VARIANCE_REASON_REQUIRED', 'Enter a reason for the cash difference before closing the shift.');
      }
      console.error('cash/close session error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not close the till shift.');
    }
  });

  router.post('/sessions/:id/reconcile', requireAuth, requireRole(...managerRoles), async (req, res) => {
    const body = parseBody(ReconcileSessionSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth as { userId: string };
    try {
      const session = await prisma.$transaction(async (tx) => {
        const updated = await tx.cashSession.updateMany({
          where: { id: req.params.id, businessId, status: 'CLOSED' },
          data: { status: 'RECONCILED', reconciledById: auth.userId },
        });
        if (updated.count !== 1) throw new Error('CASH_SESSION_NOT_CLOSED');
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'CASH_SESSION_RECONCILED',
            entityType: 'CASH_SESSION',
            entityId: req.params.id,
            afterJson: { note: body.note },
          },
        });
        return tx.cashSession.findFirstOrThrow({
          where: { id: req.params.id, businessId },
          include: sessionInclude,
        });
      });
      return send200(res, { data: mapSession(session) });
    } catch (error) {
      if (error instanceof Error && error.message === 'CASH_SESSION_NOT_CLOSED') {
        return sendError(res, 409, 'CASH_SESSION_NOT_CLOSED', 'Only a closed shift can be reconciled.');
      }
      console.error('cash/reconcile session error:', error);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not reconcile the till shift.');
    }
  });

  return router;
}
