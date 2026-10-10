/**
 * Delivery module — delivery config, order lifecycle, rider management, and
 * rider-scoped endpoints.
 *
 * RIDER gate: authenticated RIDERs may only access paths under /rider/ OR
 * the PATCH /orders/:id/status route (so riders can advance their own orders).
 * All other paths require MANAGER, OWNER, or SUPER_ADMIN unless noted.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { Decimal } from '@prisma/client/runtime/library';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';
import type { AuthLocals } from '../../lib/auth.middleware';

// ─── Constants ────────────────────────────────────────────────────────────────

const DELIVERY_KEYS = ['delivery.base_fee', 'delivery.distance_topup_rate'] as const;

// ─── Zod schemas ──────────────────────────────────────────────────────────────

const DeliveryConfigSchema = z.object({
  baseFee: z.number().nonnegative(),
  distanceTopupRate: z.number().nonnegative(),
});

const CreateDeliveryOrderSchema = z.object({
  saleId: z.string().uuid().optional(),
  recipientName: z.string().trim().min(1).max(120),
  recipientPhone: z.string().min(9).max(24),
  deliveryAddress: z.string().trim().min(1),
  distanceKm: z.number().nonnegative(),
});

const ListOrdersSchema = z.object({
  status: z.string().optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

const AssignRiderSchema = z.object({
  riderId: z.string().uuid(),
});

const UpdateStatusSchema = z.object({
  status: z.enum(['IN_TRANSIT', 'DELIVERED', 'FAILED']),
  failureReason: z.string().optional(),
});

const CancelOrderSchema = z.object({
  reason: z.string().min(1),
});

const CreatePayoutSchema = z.object({
  amount: z.number().positive(),
  mpesaPhone: z.string().min(9).max(24),
});

const PaginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

// ─── Internal types ───────────────────────────────────────────────────────────

interface RouteError {
  status: number;
  code: string;
  message: string;
}

type TxResult<T> = { ok: true; data: T } | { ok: false; error: RouteError };

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Extract a numeric value from a BusinessSetting JSON field. */
function getSettingValue(settings: { key: string; value: unknown }[], key: string): number {
  const row = settings.find((s) => s.key === key);
  if (!row) return 0;
  const raw = row.value as { value?: unknown };
  return typeof raw?.value === 'number' ? raw.value : 0;
}

/**
 * Normalise a Kenyan phone number to 12-digit format (254XXXXXXXXX).
 * Throws an Error for unrecognised formats.
 */
function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, '');
  if (digits.startsWith('254') && digits.length === 12) return digits;
  if (digits.startsWith('0') && digits.length === 10) return `254${digits.slice(1)}`;
  if (digits.startsWith('7') && digits.length === 9) return `254${digits}`;
  throw new Error('Enter a valid Kenyan phone number.');
}

// ─── Router factory ───────────────────────────────────────────────────────────

export function deliveryRouter(businessId: string): Router {
  const router = ExpressRouter();

  // ─── RIDER gate ─────────────────────────────────────────────────────────────
  // RIDERs are only permitted on:
  //   • paths that start with /rider/
  //   • PATCH /orders/:id/status  (so a rider can mark pick-up / delivered)
  // Any other request from a RIDER role gets 403.
  router.use((req, res, next) => {
    const auth = res.locals.auth as AuthLocals;
    if (auth?.role === 'RIDER') {
      const isRiderPath = req.path.startsWith('/rider/');
      const isStatusUpdate = req.method === 'PATCH' && /^\/orders\/[^/]+\/status$/.test(req.path);
      if (!isRiderPath && !isStatusUpdate) {
        return sendError(res, 403, 'FORBIDDEN', 'Your account does not have permission to do this.');
      }
    }
    return next();
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group 0 — Delivery configuration
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /delivery/config
  router.get('/config', requireAuth, async (_req, res) => {
    try {
      const settings = await prisma.businessSetting.findMany({
        where: { businessId, key: { in: [...DELIVERY_KEYS] } },
      });

      return send200(res, {
        baseFee: getSettingValue(settings, 'delivery.base_fee'),
        distanceTopupRate: getSettingValue(settings, 'delivery.distance_topup_rate'),
      });
    } catch (err) {
      console.error('delivery/config GET error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch delivery config.');
    }
  });

  // PUT /delivery/config
  router.put('/config', requireAuth, requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'), async (req, res) => {
    const body = parseBody(DeliveryConfigSchema, req, res);
    if (!body) return;

    const { baseFee, distanceTopupRate } = body;
    try {
      await Promise.all([
        prisma.businessSetting.upsert({
          where: { businessId_key: { businessId, key: 'delivery.base_fee' } },
          update: { value: { value: baseFee } },
          create: { businessId, key: 'delivery.base_fee', value: { value: baseFee } },
        }),
        prisma.businessSetting.upsert({
          where: { businessId_key: { businessId, key: 'delivery.distance_topup_rate' } },
          update: { value: { value: distanceTopupRate } },
          create: { businessId, key: 'delivery.distance_topup_rate', value: { value: distanceTopupRate } },
        }),
      ]);

      return send200(res, { baseFee, distanceTopupRate });
    } catch (err) {
      console.error('delivery/config PUT error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update delivery config.');
    }
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Group A — Order lifecycle
  // ═══════════════════════════════════════════════════════════════════════════

  // POST /delivery/orders — Task 5.1
  router.post(
    '/orders',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const body = parseBody(CreateDeliveryOrderSchema, req, res);
      if (!body) return;

      const auth = res.locals.auth as AuthLocals;
      const { saleId, recipientName, recipientPhone, deliveryAddress, distanceKm } = body;

      try {
        const order = await prisma.$transaction(async (tx) => {
          // 1. Read fee settings
          const settings = await tx.businessSetting.findMany({
            where: { businessId, key: { in: [...DELIVERY_KEYS] } },
          });
          const baseFeeNum = getSettingValue(settings, 'delivery.base_fee');
          const topupRateNum = getSettingValue(settings, 'delivery.distance_topup_rate');

          // 2. Compute deliveryFee using Decimal (no floats)
          const baseFee = new Decimal(baseFeeNum);
          const topupRate = new Decimal(topupRateNum);
          const deliveryFee = baseFee.add(new Decimal(distanceKm).mul(topupRate));

          // 3. Create the DeliveryOrder
          const created = await tx.deliveryOrder.create({
            data: {
              businessId,
              saleId: saleId ?? null,
              status: 'PENDING',
              recipientName,
              recipientPhone,
              deliveryAddress,
              distanceKm: new Decimal(distanceKm),
              baseFee,
              topupRate,
              deliveryFee,
              createdById: auth.userId,
            },
          });

          // 4. Write audit log
          await tx.auditLog.create({
            data: {
              businessId,
              userId: auth.userId,
              action: 'CREATE',
              entityType: 'DELIVERY_ORDER',
              entityId: created.id,
            },
          });

          return created;
        });

        return send201(res, order);
      } catch (err) {
        console.error('delivery/orders POST error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to create delivery order.');
      }
    },
  );

  // GET /delivery/orders — Task 5.4
  router.get(
    '/orders',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const query = parseQuery(ListOrdersSchema, req, res);
      if (!query) return;

      // Zod .default() guarantees these are numbers after parsing
      const page = query.page as number;
      const limit = query.limit as number;
      const status = query.status;
      const skip = (page - 1) * limit;

      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const statusFilter = status ? { status: status as any } : {};

        const [data, total] = await Promise.all([
          prisma.deliveryOrder.findMany({
            where: { businessId, ...statusFilter },
            include: { rider: { select: { fullName: true } } },
            orderBy: { createdAt: 'desc' },
            skip,
            take: limit,
          }),
          prisma.deliveryOrder.count({
            where: { businessId, ...statusFilter },
          }),
        ]);

        return send200(res, { data, meta: { total, page, limit } });
      } catch (err) {
        console.error('delivery/orders GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to list delivery orders.');
      }
    },
  );

  // GET /delivery/orders/:id — Task 5.4
  router.get(
    '/orders/:id',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      try {
        const order = await prisma.deliveryOrder.findFirst({
          where: { id: req.params['id'], businessId },
          include: { rider: { select: { fullName: true } } },
        });

        if (!order) {
          return sendError(res, 404, 'NOT_FOUND', 'Delivery order not found.');
        }

        return send200(res, order);
      } catch (err) {
        console.error('delivery/orders/:id GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch delivery order.');
      }
    },
  );

  // PATCH /delivery/orders/:id/assign — Task 5.6
  router.patch(
    '/orders/:id/assign',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const body = parseBody(AssignRiderSchema, req, res);
      if (!body) return;

      const auth = res.locals.auth as AuthLocals;
      const { riderId } = body;
      const orderId = req.params['id'] as string;

      try {
        const result = await prisma.$transaction(async (tx): Promise<TxResult<ReturnType<typeof tx.deliveryOrder.update> extends Promise<infer T> ? T : never>> => {
          // Fetch order
          const order = await tx.deliveryOrder.findFirst({
            where: { id: orderId, businessId },
          });
          if (!order) {
            return { ok: false, error: { status: 404, code: 'NOT_FOUND', message: 'Delivery order not found.' } };
          }

          // Validate transition
          if (order.status !== 'PENDING') {
            return {
              ok: false,
              error: { status: 422, code: 'INVALID_TRANSITION', message: `Cannot assign a rider to an order in status '${order.status}'.` },
            };
          }

          // Validate rider
          const rider = await tx.user.findUnique({
            where: { id: riderId },
            select: { id: true, role: true, active: true },
          });
          if (!rider || !rider.active || rider.role !== 'RIDER') {
            return {
              ok: false,
              error: { status: 422, code: 'INVALID_RIDER', message: 'The selected user is not an active rider.' },
            };
          }

          // Update order
          const updated = await tx.deliveryOrder.update({
            where: { id: order.id },
            data: { status: 'ASSIGNED', riderId, assignedAt: new Date() },
          });

          // Audit log
          await tx.auditLog.create({
            data: {
              businessId,
              userId: auth.userId,
              action: 'ASSIGN',
              entityType: 'DELIVERY_ORDER',
              entityId: order.id,
            },
          });

          return { ok: true, data: updated };
        });

        if (!result.ok) {
          return sendError(res, result.error.status, result.error.code, result.error.message);
        }
        return send200(res, result.data);
      } catch (err) {
        console.error('delivery/orders/:id/assign PATCH error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to assign rider.');
      }
    },
  );

  // PATCH /delivery/orders/:id/status — Task 5.8
  // Note: RIDER role is allowed here (gate exception above).
  // A RIDER may only advance orders assigned to them.
  router.patch(
    '/orders/:id/status',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN', 'RIDER'),
    async (req, res) => {
      const body = parseBody(UpdateStatusSchema, req, res);
      if (!body) return;

      const auth = res.locals.auth as AuthLocals;
      const { status: requestedStatus, failureReason } = body;
      const orderId = req.params['id'] as string;

      try {
        const result = await prisma.$transaction(async (tx): Promise<TxResult<ReturnType<typeof tx.deliveryOrder.update> extends Promise<infer T> ? T : never>> => {
          const order = await tx.deliveryOrder.findFirst({
            where: { id: orderId, businessId },
          });
          if (!order) {
            return { ok: false, error: { status: 404, code: 'NOT_FOUND', message: 'Delivery order not found.' } };
          }

          // RIDER isolation: a rider may only update their own assigned orders
          if (auth.role === 'RIDER' && order.riderId !== auth.userId) {
            return {
              ok: false,
              error: { status: 403, code: 'FORBIDDEN', message: 'You can only update orders assigned to you.' },
            };
          }

          // State machine validation
          const current = order.status;
          const updateData: {
            status: typeof requestedStatus;
            pickedUpAt?: Date;
            deliveredAt?: Date;
            failureReason?: string | null;
          } = { status: requestedStatus };

          if (current === 'ASSIGNED' && requestedStatus === 'IN_TRANSIT') {
            updateData.pickedUpAt = new Date();
          } else if (current === 'ASSIGNED' && requestedStatus === 'FAILED') {
            updateData.failureReason = failureReason ?? null;
          } else if (current === 'IN_TRANSIT' && requestedStatus === 'DELIVERED') {
            updateData.deliveredAt = new Date();
          } else if (current === 'IN_TRANSIT' && requestedStatus === 'FAILED') {
            updateData.failureReason = failureReason ?? null;
          } else {
            return {
              ok: false,
              error: {
                status: 422,
                code: 'INVALID_TRANSITION',
                message: `Cannot transition from '${current}' to '${requestedStatus}'.`,
              },
            };
          }

          // Update order
          const updated = await tx.deliveryOrder.update({
            where: { id: order.id },
            data: updateData,
          });

          // On DELIVERED: create RiderLedger CREDIT
          if (requestedStatus === 'DELIVERED' && order.riderId) {
            const last = await tx.riderLedger.findFirst({
              where: { riderId: order.riderId, businessId },
              orderBy: { createdAt: 'desc' },
              select: { balance: true },
            });
            const prevBalance = last ? new Decimal(last.balance.toString()) : new Decimal(0);
            const newBalance = prevBalance.add(new Decimal(order.deliveryFee.toString()));

            await tx.riderLedger.create({
              data: {
                businessId,
                riderId: order.riderId,
                entryType: 'CREDIT',
                amount: order.deliveryFee,
                balance: newBalance,
                entityType: 'DELIVERY',
                entityId: order.id,
                createdById: auth.userId,
              },
            });
          }

          // Audit log
          await tx.auditLog.create({
            data: {
              businessId,
              userId: auth.userId,
              action: `STATUS_${requestedStatus}`,
              entityType: 'DELIVERY_ORDER',
              entityId: order.id,
            },
          });

          return { ok: true, data: updated };
        });

        if (!result.ok) {
          return sendError(res, result.error.status, result.error.code, result.error.message);
        }
        return send200(res, result.data);
      } catch (err) {
        console.error('delivery/orders/:id/status PATCH error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to update order status.');
      }
    },
  );

  // PATCH /delivery/orders/:id/cancel — Task 5.11
  router.patch(
    '/orders/:id/cancel',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const body = parseBody(CancelOrderSchema, req, res);
      if (!body) return;

      const auth = res.locals.auth as AuthLocals;
      const { reason } = body;
      const orderId = req.params['id'] as string;

      try {
        const result = await prisma.$transaction(async (tx): Promise<TxResult<ReturnType<typeof tx.deliveryOrder.update> extends Promise<infer T> ? T : never>> => {
          const order = await tx.deliveryOrder.findFirst({
            where: { id: orderId, businessId },
          });
          if (!order) {
            return { ok: false, error: { status: 404, code: 'NOT_FOUND', message: 'Delivery order not found.' } };
          }

          if (order.status !== 'PENDING' && order.status !== 'ASSIGNED') {
            return {
              ok: false,
              error: {
                status: 422,
                code: 'INVALID_TRANSITION',
                message: `Cannot cancel an order in status '${order.status}'.`,
              },
            };
          }

          const updated = await tx.deliveryOrder.update({
            where: { id: order.id },
            data: { status: 'CANCELLED', failureReason: reason },
          });

          await tx.auditLog.create({
            data: {
              businessId,
              userId: auth.userId,
              action: 'CANCEL',
              entityType: 'DELIVERY_ORDER',
              entityId: order.id,
            },
          });

          return { ok: true, data: updated };
        });

        if (!result.ok) {
          return sendError(res, result.error.status, result.error.code, result.error.message);
        }
        return send200(res, result.data);
      } catch (err) {
        console.error('delivery/orders/:id/cancel PATCH error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to cancel delivery order.');
      }
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // Group B — Rider management
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /delivery/riders — Task 7.1
  router.get('/riders', requireAuth, requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'), async (_req, res) => {
    try {
      const riders = await prisma.user.findMany({
        where: { active: true, role: 'RIDER' },
        select: { id: true, fullName: true, phone: true, role: true },
        orderBy: { fullName: 'asc' },
      });

      // Compute signed balance per rider via raw SQL (CREDIT = +, DEBIT = -)
      type BalanceRow = { riderId: string; balance: string | null };
      const balanceRows = await prisma.$queryRaw<BalanceRow[]>`
        SELECT "riderId",
          SUM(CASE WHEN "entryType" = 'CREDIT' THEN amount ELSE -amount END) as balance
        FROM rider_ledger
        WHERE "businessId" = ${businessId}::uuid
        GROUP BY "riderId"
      `;

      const balanceMap = new Map(balanceRows.map((r) => [r.riderId, r.balance ?? '0']));

      const result = riders.map((r) => ({
        ...r,
        pendingBalance: new Decimal(balanceMap.get(r.id) ?? '0').toFixed(2),
      }));

      return send200(res, result);
    } catch (err) {
      console.error('delivery/riders GET error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch riders.');
    }
  });

  // GET /delivery/riders/:riderId/ledger — Task 7.1
  router.get(
    '/riders/:riderId/ledger',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const query = parseQuery(PaginationSchema, req, res);
      if (!query) return;

      const page = query.page as number;
      const limit = query.limit as number;
      const skip = (page - 1) * limit;
      const riderId = req.params['riderId'] as string;

      try {
        const [data, total] = await Promise.all([
          prisma.riderLedger.findMany({
            where: { riderId, businessId },
            orderBy: { createdAt: 'desc' },
            skip,
            take: limit,
          }),
          prisma.riderLedger.count({ where: { riderId, businessId } }),
        ]);

        return send200(res, { data, meta: { total, page, limit } });
      } catch (err) {
        console.error('delivery/riders/:riderId/ledger GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch rider ledger.');
      }
    },
  );

  // GET /delivery/riders/:riderId/payouts — Task 7.3
  router.get(
    '/riders/:riderId/payouts',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const query = parseQuery(PaginationSchema, req, res);
      if (!query) return;

      const page = query.page as number;
      const limit = query.limit as number;
      const skip = (page - 1) * limit;
      const riderId = req.params['riderId'] as string;

      try {
        const [data, total] = await Promise.all([
          prisma.riderPayout.findMany({
            where: { riderId, businessId },
            orderBy: { initiatedAt: 'desc' },
            skip,
            take: limit,
          }),
          prisma.riderPayout.count({ where: { riderId, businessId } }),
        ]);

        return send200(res, { data, meta: { total, page, limit } });
      } catch (err) {
        console.error('delivery/riders/:riderId/payouts GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch rider payouts.');
      }
    },
  );

  // POST /delivery/riders/:riderId/payout — Task 7.3
  router.post(
    '/riders/:riderId/payout',
    requireAuth,
    requireRole('MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const body = parseBody(CreatePayoutSchema, req, res);
      if (!body) return;

      const auth = res.locals.auth as AuthLocals;
      const { amount, mpesaPhone } = body;
      const riderId = req.params['riderId'] as string;

      // Normalise phone
      let normalizedPhone: string;
      try {
        normalizedPhone = normalizePhone(mpesaPhone);
      } catch {
        return sendError(res, 400, 'INVALID_PHONE', 'Enter a valid Kenyan phone number.');
      }

      try {
        // Compute available balance via raw SQL
        type BalanceRow = { balance: string | null };
        const [balanceRow] = await prisma.$queryRaw<BalanceRow[]>`
          SELECT SUM(CASE WHEN "entryType" = 'CREDIT' THEN amount ELSE -amount END) as balance
          FROM rider_ledger
          WHERE "businessId" = ${businessId}::uuid
            AND "riderId" = ${riderId}::uuid
        `;
        const availableBalance = new Decimal(balanceRow?.balance ?? '0');
        const payoutAmount = new Decimal(amount);

        if (payoutAmount.greaterThan(availableBalance)) {
          return sendError(res, 422, 'INSUFFICIENT_BALANCE', "Payout amount exceeds rider's available balance.");
        }

        const payout = await prisma.$transaction(async (tx) => {
          // Get last ledger entry for running balance
          const last = await tx.riderLedger.findFirst({
            where: { riderId, businessId },
            orderBy: { createdAt: 'desc' },
            select: { balance: true },
          });
          const prevBalance = last ? new Decimal(last.balance.toString()) : new Decimal(0);
          const newBalance = prevBalance.sub(payoutAmount);

          // Insert DEBIT ledger entry first (to obtain its id for the payout FK)
          const ledgerEntry = await tx.riderLedger.create({
            data: {
              businessId,
              riderId,
              entryType: 'DEBIT',
              amount: payoutAmount,
              balance: newBalance,
              entityType: 'DELIVERY',
              createdById: auth.userId,
            },
          });

          // TODO (Task 7.5): Initiate M-Pesa B2C via Daraja integration.
          // For now, create the payout in PENDING status with no checkoutRequestId.
          const createdPayout = await tx.riderPayout.create({
            data: {
              businessId,
              riderId,
              amount: payoutAmount,
              mpesaPhone: normalizedPhone,
              status: 'PENDING',
              checkoutRequestId: null,
              riderLedgerEntryId: ledgerEntry.id,
            },
          });

          return createdPayout;
        });

        return send201(res, payout);
      } catch (err) {
        console.error('delivery/riders/:riderId/payout POST error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to initiate payout.');
      }
    },
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // Group C — Rider-scoped endpoints (RIDER role only)
  // ═══════════════════════════════════════════════════════════════════════════

  // GET /delivery/rider/orders — Task 8.1
  router.get('/rider/orders', requireAuth, requireRole('RIDER'), async (_req, res) => {
    const auth = res.locals.auth as AuthLocals;
    try {
      const orders = await prisma.deliveryOrder.findMany({
        where: {
          businessId,
          riderId: auth.userId,
          status: { in: ['ASSIGNED', 'IN_TRANSIT'] },
        },
        orderBy: { createdAt: 'desc' },
      });

      return send200(res, orders);
    } catch (err) {
      console.error('delivery/rider/orders GET error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch rider orders.');
    }
  });

  // GET /delivery/rider/earnings — Task 8.1
  router.get('/rider/earnings', requireAuth, requireRole('RIDER'), async (_req, res) => {
    const auth = res.locals.auth as AuthLocals;
    try {
      type BalanceRow = { balance: string | null };
      const [balanceRow] = await prisma.$queryRaw<BalanceRow[]>`
        SELECT SUM(CASE WHEN "entryType" = 'CREDIT' THEN amount ELSE -amount END) as balance
        FROM rider_ledger
        WHERE "businessId" = ${businessId}::uuid
          AND "riderId" = ${auth.userId}::uuid
      `;
      const pendingBalance = new Decimal(balanceRow?.balance ?? '0').toFixed(2);

      const entries = await prisma.riderLedger.findMany({
        where: { riderId: auth.userId, businessId },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });

      return send200(res, { pendingBalance, entries });
    } catch (err) {
      console.error('delivery/rider/earnings GET error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch rider earnings.');
    }
  });

  return router;
}
