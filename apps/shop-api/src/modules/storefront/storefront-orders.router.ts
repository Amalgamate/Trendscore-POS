import { createHash } from 'node:crypto';
import { Prisma, type PrismaClient } from '@prisma/client';
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { ulid } from 'ulid';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';
import type { AuthLocals } from '../../lib/auth.middleware';

const ORDER_HOLD_MS = 15 * 60 * 1000;
const STOREFRONT_SETTING_KEY = 'storefront_profile';

const phoneSchema = z
  .string()
  .trim()
  .min(9)
  .max(20)
  .regex(/^(?:(?:\+?254|0)[ -]?)?[17](?:[ -]?\d){8}$/, 'Enter a valid Kenyan mobile number.');

export const CreateStorefrontOrderSchema = z
  .object({
    idempotencyKey: z.string().uuid(),
    customerName: z.string().trim().min(2).max(120),
    customerPhone: phoneSchema,
    customerEmail: z.union([z.string().trim().email().max(254), z.literal('')]).optional(),
    fulfillmentMethod: z.enum(['DELIVERY', 'PICKUP']),
    deliveryAddress: z.string().trim().min(5).max(500).optional(),
    privacyAccepted: z.literal(true),
    lines: z
      .array(
        z.object({
          productId: z.string().uuid(),
          quantity: z.number().int().positive().max(999),
        }),
      )
      .min(1)
      .max(50),
  })
  .superRefine((body, ctx) => {
    if (body.fulfillmentMethod === 'DELIVERY' && !body.deliveryAddress) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['deliveryAddress'],
        message: 'A delivery address is required.',
      });
    }
    const productIds = body.lines.map((line) => line.productId);
    if (new Set(productIds).size !== productIds.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['lines'],
        message: 'Each product can appear only once.',
      });
    }
  });

const OrderAccessSchema = z.object({
  accessKey: z.string().uuid(),
});

const OrderIdSchema = z.string().uuid();
const StaffOrdersQuerySchema = z.object({
  status: z.enum(['AWAITING_PAYMENT', 'CANCELLED', 'EXPIRED']).optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

type CreateStorefrontOrderInput = z.infer<typeof CreateStorefrontOrderSchema>;
type StorefrontOrderTransaction = Prisma.TransactionClient;

class StorefrontOrderError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

export function normalizeStorefrontPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  const local = digits.startsWith('254')
    ? digits.slice(3)
    : digits.startsWith('0')
      ? digits.slice(1)
      : digits;
  return `+254${local}`;
}

export function hashOrderSecret(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

export function storefrontOrderRequestHash(
  input: CreateStorefrontOrderInput,
): string {
  const canonical = {
    customerName: input.customerName.trim(),
    customerPhone: normalizeStorefrontPhone(input.customerPhone),
    customerEmail: input.customerEmail?.trim().toLowerCase() || null,
    fulfillmentMethod: input.fulfillmentMethod,
    deliveryAddress: input.fulfillmentMethod === 'DELIVERY'
      ? input.deliveryAddress?.trim() ?? null
      : null,
    lines: [...input.lines]
      .sort((a, b) => a.productId.localeCompare(b.productId))
      .map(({ productId, quantity }) => ({ productId, quantity })),
  };
  return hashOrderSecret(JSON.stringify(canonical));
}

async function lockProducts(
  tx: StorefrontOrderTransaction,
  businessId: string,
  productIds: string[],
): Promise<void> {
  const uniqueIds = [...new Set(productIds)].sort();
  if (uniqueIds.length === 0) return;
  const locked = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT "id"
    FROM "products"
    WHERE "businessId" = ${businessId}::uuid
      AND "id" IN (${Prisma.join(uniqueIds.map((id) => Prisma.sql`${id}::uuid`))})
    ORDER BY "id"
    FOR UPDATE
  `;
  if (locked.length !== uniqueIds.length) {
    throw new StorefrontOrderError(
      409,
      'PRODUCTS_CHANGED',
      'One or more products are no longer available. Refresh your bag and try again.',
    );
  }
}

async function releaseOrderStock(
  tx: StorefrontOrderTransaction,
  order: {
    orderNumber: string;
    businessId: string;
    items: Array<{
      productId: string;
      quantity: Prisma.Decimal;
      unitCost: Prisma.Decimal;
    }>;
  },
  note: string,
  createdById?: string,
): Promise<void> {
  for (const item of order.items) {
    const product = await tx.product.update({
      where: { id: item.productId },
      data: { stock: { increment: item.quantity } },
      select: { stock: true },
    });
    await tx.stockMovement.create({
      data: {
        businessId: order.businessId,
        productId: item.productId,
        type: 'STOREFRONT_RELEASE',
        quantity: item.quantity,
        balanceAfter: product.stock,
        unitCost: item.unitCost,
        reference: order.orderNumber,
        note,
        ...(createdById ? { createdById } : {}),
      },
    });
  }
}

export async function expirePendingStorefrontOrders(
  businessId: string,
): Promise<void> {
  const now = new Date();
  const candidates = await prisma.storefrontOrder.findMany({
    where: {
      businessId,
      status: 'AWAITING_PAYMENT',
      expiresAt: { lte: now },
    },
    include: { items: true },
    orderBy: { expiresAt: 'asc' },
    take: 100,
  });
  if (candidates.length === 0) return;

  await prisma.$transaction(async (tx) => {
    const productIds = candidates.flatMap((order) =>
      order.items.map((item) => item.productId),
    );
    await lockProducts(tx, businessId, productIds);
    const currentOrders = await tx.storefrontOrder.findMany({
      where: {
        id: { in: candidates.map((order) => order.id) },
        businessId,
        status: 'AWAITING_PAYMENT',
        expiresAt: { lte: now },
      },
      include: { items: true },
    });
    for (const order of currentOrders) {
      const changed = await tx.storefrontOrder.updateMany({
        where: {
          id: order.id,
          businessId,
          status: 'AWAITING_PAYMENT',
          expiresAt: { lte: now },
        },
        data: { status: 'EXPIRED' },
      });
      if (changed.count !== 1) continue;
      await releaseOrderStock(tx, order, 'Expired storefront order stock hold.');
      await tx.storefrontOrderEvent.create({
        data: {
          orderId: order.id,
          fromStatus: 'AWAITING_PAYMENT',
          toStatus: 'EXPIRED',
          detail: 'The 15-minute payment hold expired. Reserved stock was released.',
        },
      });
    }
  });
}

function orderResponse(order: {
  id: string;
  orderNumber: string;
  status: string;
  customerName: string;
  customerPhone: string;
  customerEmail: string | null;
  fulfillmentMethod: string;
  deliveryAddress: string | null;
  subtotal: Prisma.Decimal;
  total: Prisma.Decimal;
  expiresAt: Date;
  createdAt: Date;
  items: Array<{
    productName: string;
    variantLabel: string | null;
    quantity: Prisma.Decimal;
    unitPrice: Prisma.Decimal;
    lineTotal: Prisma.Decimal;
  }>;
  statusEvents: Array<{
    fromStatus: string | null;
    toStatus: string;
    detail: string;
    createdAt: Date;
  }>;
}) {
  return {
    id: order.id,
    orderNumber: order.orderNumber,
    status: order.status,
    customerName: order.customerName,
    customerPhone: order.customerPhone,
    customerEmail: order.customerEmail,
    fulfillmentMethod: order.fulfillmentMethod,
    deliveryAddress: order.deliveryAddress,
    subtotal: Number(order.subtotal),
    total: Number(order.total),
    expiresAt: order.expiresAt,
    createdAt: order.createdAt,
    items: order.items.map((item) => ({
      productName: item.productName,
      variantLabel: item.variantLabel,
      quantity: Number(item.quantity),
      unitPrice: Number(item.unitPrice),
      lineTotal: Number(item.lineTotal),
    })),
    statusEvents: order.statusEvents.map((event) => ({
      fromStatus: event.fromStatus,
      toStatus: event.toStatus,
      detail: event.detail,
      createdAt: event.createdAt,
    })),
  };
}

async function findOrderByAccessKey(
  client: PrismaClient | StorefrontOrderTransaction,
  businessId: string,
  orderId: string,
  accessKey: string,
) {
  return client.storefrontOrder.findFirst({
    where: {
      id: orderId,
      businessId,
      idempotencyKeyHash: hashOrderSecret(accessKey),
    },
    include: {
      items: { orderBy: { productName: 'asc' } },
      statusEvents: { orderBy: { createdAt: 'asc' } },
    },
  });
}

export function storefrontOrdersRouter(businessId: string): Router {
  const router = ExpressRouter();

  router.get(
    '/',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const parsed = StaffOrdersQuerySchema.safeParse(req.query);
      if (!parsed.success) {
        return sendError(res, 422, 'INVALID_QUERY', 'Check the order filters and try again.');
      }
      const { status, page, limit } = parsed.data;
      const where = { businessId, ...(status ? { status } : {}) };
      try {
        await expirePendingStorefrontOrders(businessId);
        const [orders, total] = await Promise.all([
          prisma.storefrontOrder.findMany({
            where,
            include: {
              items: { orderBy: { productName: 'asc' } },
              statusEvents: { orderBy: { createdAt: 'asc' } },
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            skip: (page - 1) * limit,
            take: limit,
          }),
          prisma.storefrontOrder.count({ where }),
        ]);
        return send200(res, {
          data: orders.map(orderResponse),
          meta: { total, page, limit },
        });
      } catch (err) {
        console.error('storefront/orders staff GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Could not load storefront orders.');
      }
    },
  );

  router.get(
    '/:id',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const orderId = OrderIdSchema.safeParse(req.params['id']);
      if (!orderId.success) {
        return sendError(res, 422, 'INVALID_ORDER', 'This order reference is invalid.');
      }
      try {
        const order = await prisma.storefrontOrder.findFirst({
          where: { id: orderId.data, businessId },
          include: {
            items: { orderBy: { productName: 'asc' } },
            statusEvents: { orderBy: { createdAt: 'asc' } },
          },
        });
        if (!order) return sendError(res, 404, 'NOT_FOUND', 'Order not found.');
        return send200(res, { data: orderResponse(order) });
      } catch (err) {
        console.error('storefront/orders staff detail GET error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Could not load this storefront order.');
      }
    },
  );

  router.patch(
    '/:id/cancel',
    requireAuth,
    requireRole('CASHIER', 'MANAGER', 'OWNER', 'SUPER_ADMIN'),
    async (req, res) => {
      const auth = res.locals.auth as AuthLocals;
      const orderId = OrderIdSchema.safeParse(req.params['id']);
      if (!orderId.success) {
        return sendError(res, 422, 'INVALID_ORDER', 'This order reference is invalid.');
      }
      try {
        await expirePendingStorefrontOrders(businessId);
        const initialOrder = await prisma.storefrontOrder.findFirst({
          where: { id: orderId.data, businessId },
          include: { items: true },
        });
        if (!initialOrder) {
          return sendError(res, 404, 'NOT_FOUND', 'Order not found.');
        }
        const result = await prisma.$transaction(async (tx) => {
          await lockProducts(
            tx,
            businessId,
            initialOrder.items.map((item) => item.productId),
          );
          const changed = await tx.storefrontOrder.updateMany({
            where: {
              id: initialOrder.id,
              businessId,
              status: 'AWAITING_PAYMENT',
              expiresAt: { gt: new Date() },
            },
            data: { status: 'CANCELLED' },
          });
          if (changed.count === 1) {
            await releaseOrderStock(
              tx,
              initialOrder,
              `Staff cancelled unpaid storefront order ${initialOrder.orderNumber}.`,
              auth.userId,
            );
            await tx.storefrontOrderEvent.create({
              data: {
                orderId: initialOrder.id,
                fromStatus: 'AWAITING_PAYMENT',
                toStatus: 'CANCELLED',
                detail: `Cancelled by ${auth.name}. Reserved stock was released.`,
              },
            });
          }
          const order = await tx.storefrontOrder.findUniqueOrThrow({
            where: { id: initialOrder.id },
            include: {
              items: { orderBy: { productName: 'asc' } },
              statusEvents: { orderBy: { createdAt: 'asc' } },
            },
          });
          return { changed: changed.count === 1, order };
        });
        if (!result.changed && result.order.status !== 'CANCELLED') {
          return sendError(
            res,
            409,
            'ORDER_NOT_CANCELLABLE',
            `This order is ${result.order.status.toLowerCase()} and can no longer be cancelled.`,
          );
        }
        return send200(res, { data: orderResponse(result.order) });
      } catch (err) {
        if (err instanceof StorefrontOrderError) {
          return sendError(res, err.status, err.code, err.message);
        }
        console.error('storefront/orders/:id staff cancel PATCH error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Could not cancel this order right now.');
      }
    },
  );

  router.post('/', async (req, res) => {
    const parsed = CreateStorefrontOrderSchema.safeParse(req.body);
    if (!parsed.success) {
      return sendError(
        res,
        422,
        'INVALID_ORDER',
        parsed.error.issues[0]?.message ?? 'Check your order details and try again.',
      );
    }
    const body = parsed.data;
    const accessKeyHash = hashOrderSecret(body.idempotencyKey);
    const requestHash = storefrontOrderRequestHash(body);

    try {
      await expirePendingStorefrontOrders(businessId);
      const order = await prisma.$transaction(async (tx) => {
        const existing = await tx.storefrontOrder.findUnique({
          where: { idempotencyKeyHash: accessKeyHash },
          include: {
            items: { orderBy: { productName: 'asc' } },
            statusEvents: { orderBy: { createdAt: 'asc' } },
          },
        });
        if (existing) {
          if (existing.requestHash !== requestHash) {
            throw new StorefrontOrderError(
              409,
              'IDEMPOTENCY_KEY_REUSED',
              'This checkout key belongs to a different order. Refresh checkout and try again.',
            );
          }
          return { order: existing, replay: true };
        }

        const profileSetting = await tx.businessSetting.findUnique({
          where: {
            businessId_key: {
              businessId,
              key: STOREFRONT_SETTING_KEY,
            },
          },
          select: { value: true },
        });
        const profile = profileSetting?.value;
        const fulfillmentEnabled =
          typeof profile === 'object' &&
          profile !== null &&
          !Array.isArray(profile) &&
          profile[body.fulfillmentMethod === 'DELIVERY'
            ? 'deliveryEnabled'
            : 'pickupEnabled'] === true;
        if (!fulfillmentEnabled) {
          throw new StorefrontOrderError(
            422,
            'FULFILLMENT_UNAVAILABLE',
            'That delivery or pickup option is not currently offered by this shop.',
          );
        }

        const productIds = body.lines.map((line) => line.productId).sort();
        await lockProducts(tx, businessId, productIds);
        const concurrentReplay = await tx.storefrontOrder.findUnique({
          where: { idempotencyKeyHash: accessKeyHash },
          include: {
            items: { orderBy: { productName: 'asc' } },
            statusEvents: { orderBy: { createdAt: 'asc' } },
          },
        });
        if (concurrentReplay) {
          if (concurrentReplay.requestHash !== requestHash) {
            throw new StorefrontOrderError(
              409,
              'IDEMPOTENCY_KEY_REUSED',
              'This checkout key belongs to a different order. Refresh checkout and try again.',
            );
          }
          return { order: concurrentReplay, replay: true };
        }
        const products = await tx.product.findMany({
          where: {
            id: { in: productIds },
            businessId,
            active: true,
            isPublished: true,
          },
        });
        if (products.length !== productIds.length) {
          throw new StorefrontOrderError(
            409,
            'PRODUCTS_CHANGED',
            'One or more products are no longer available. Refresh your bag and try again.',
          );
        }
        const productById = new Map(products.map((product) => [product.id, product]));
        const now = new Date();
        const expiresAt = new Date(now.getTime() + ORDER_HOLD_MS);
        let total = new Prisma.Decimal(0);
        const reservedItems = body.lines.map((line) => {
          const product = productById.get(line.productId)!;
          if (product.stock.lt(line.quantity)) {
            throw new StorefrontOrderError(
              409,
              'STOCK_CHANGED',
              `${product.name} no longer has enough stock. Update your bag and try again.`,
            );
          }
          const lineTotal = product.salePrice
            .mul(line.quantity)
            .toDecimalPlaces(2);
          total = total.plus(lineTotal);
          return {
            product,
            quantity: new Prisma.Decimal(line.quantity),
            lineTotal,
          };
        });
        const orderNumber = `WEB-${ulid()}`;
        const created = await tx.storefrontOrder.create({
          data: {
            businessId,
            orderNumber,
            idempotencyKeyHash: accessKeyHash,
            requestHash,
            customerName: body.customerName,
            customerPhone: normalizeStorefrontPhone(body.customerPhone),
            customerEmail: body.customerEmail?.trim().toLowerCase() || null,
            fulfillmentMethod: body.fulfillmentMethod,
            deliveryAddress: body.fulfillmentMethod === 'DELIVERY'
              ? body.deliveryAddress?.trim() ?? null
              : null,
            subtotal: total,
            total,
            status: 'AWAITING_PAYMENT',
            expiresAt,
            items: {
              create: reservedItems.map(({ product, quantity, lineTotal }) => ({
                productId: product.id,
                productName: product.name,
                variantLabel: product.variantLabel,
                quantity,
                unitPrice: product.salePrice,
                unitCost: product.costPrice,
                lineTotal,
              })),
            },
            statusEvents: {
              create: {
                toStatus: 'AWAITING_PAYMENT',
                detail: 'Unpaid order placed. Stock is held for 15 minutes.',
              },
            },
          },
        });
        for (const { product, quantity } of reservedItems) {
          const newStock = product.stock.minus(quantity);
          await tx.product.update({
            where: { id: product.id },
            data: { stock: newStock },
          });
          await tx.stockMovement.create({
            data: {
              businessId,
              productId: product.id,
              type: 'STOREFRONT_RESERVATION',
              quantity: quantity.negated(),
              balanceAfter: newStock,
              unitCost: product.costPrice,
              reference: orderNumber,
              note: `Stock held for unpaid storefront order ${orderNumber}.`,
            },
          });
        }
        const completeOrder = await tx.storefrontOrder.findUniqueOrThrow({
          where: { id: created.id },
          include: {
            items: { orderBy: { productName: 'asc' } },
            statusEvents: { orderBy: { createdAt: 'asc' } },
          },
        });
        return { order: completeOrder, replay: false };
      });
      return order.replay
        ? send200(res, { data: orderResponse(order.order) })
        : send201(res, { data: orderResponse(order.order) });
    } catch (err) {
      if (err instanceof StorefrontOrderError) {
        return sendError(res, err.status, err.code, err.message);
      }
      if (
        err instanceof Prisma.PrismaClientKnownRequestError &&
        err.code === 'P2002'
      ) {
        try {
          const existing = await prisma.storefrontOrder.findUnique({
            where: { idempotencyKeyHash: accessKeyHash },
            include: {
              items: { orderBy: { productName: 'asc' } },
              statusEvents: { orderBy: { createdAt: 'asc' } },
            },
          });
          if (existing) {
            if (existing.requestHash !== requestHash) {
              return sendError(
                res,
                409,
                'IDEMPOTENCY_KEY_REUSED',
                'This checkout key belongs to a different order. Refresh checkout and try again.',
              );
            }
            return send200(res, { data: orderResponse(existing) });
          }
        } catch (lookupError) {
          console.error('storefront order idempotency lookup error:', lookupError);
        }
      }
      console.error('storefront/orders POST error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not place your order. Your bag has not been charged.');
    }
  });

  router.post('/:id/status', async (req, res) => {
    const parsed = OrderAccessSchema.safeParse(req.body);
    if (!parsed.success) {
      return sendError(res, 422, 'INVALID_ORDER_ACCESS', 'This order link is invalid.');
    }
    const orderId = OrderIdSchema.safeParse(req.params['id']);
    if (!orderId.success) {
      return sendError(res, 422, 'INVALID_ORDER', 'This order reference is invalid.');
    }
    try {
      await expirePendingStorefrontOrders(businessId);
      const order = await findOrderByAccessKey(
        prisma,
        businessId,
        orderId.data,
        parsed.data.accessKey,
      );
      if (!order) {
        return sendError(res, 404, 'NOT_FOUND', 'Order not found.');
      }
      return send200(res, { data: orderResponse(order) });
    } catch (err) {
      console.error('storefront/orders/:id/status POST error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not load this order right now.');
    }
  });

  router.post('/:id/cancel', async (req, res) => {
    const parsed = OrderAccessSchema.safeParse(req.body);
    if (!parsed.success) {
      return sendError(res, 422, 'INVALID_ORDER_ACCESS', 'This order link is invalid.');
    }
    const orderId = OrderIdSchema.safeParse(req.params['id']);
    if (!orderId.success) {
      return sendError(res, 422, 'INVALID_ORDER', 'This order reference is invalid.');
    }
    try {
      await expirePendingStorefrontOrders(businessId);
      const initialOrder = await findOrderByAccessKey(
        prisma,
        businessId,
        orderId.data,
        parsed.data.accessKey,
      );
      if (!initialOrder) {
        return sendError(res, 404, 'NOT_FOUND', 'Order not found.');
      }
      const result = await prisma.$transaction(async (tx) => {
        await lockProducts(
          tx,
          businessId,
          initialOrder.items.map((item) => item.productId),
        );
        const changed = await tx.storefrontOrder.updateMany({
          where: {
            id: initialOrder.id,
            businessId,
            status: 'AWAITING_PAYMENT',
            expiresAt: { gt: new Date() },
          },
          data: { status: 'CANCELLED' },
        });
        if (changed.count === 1) {
          await releaseOrderStock(
            tx,
            initialOrder,
            'Customer cancelled unpaid storefront order.',
          );
          await tx.storefrontOrderEvent.create({
            data: {
              orderId: initialOrder.id,
              fromStatus: 'AWAITING_PAYMENT',
              toStatus: 'CANCELLED',
              detail: 'Order cancelled. Reserved stock was released.',
            },
          });
        }
        const order = await tx.storefrontOrder.findUniqueOrThrow({
          where: { id: initialOrder.id },
          include: {
            items: { orderBy: { productName: 'asc' } },
            statusEvents: { orderBy: { createdAt: 'asc' } },
          },
        });
        return { changed: changed.count === 1, order };
      });
      if (!result.changed) {
        return sendError(
          res,
          409,
          'ORDER_NOT_CANCELLABLE',
          `This order is ${result.order.status.toLowerCase()} and can no longer be cancelled.`,
        );
      }
      return send200(res, { data: orderResponse(result.order) });
    } catch (err) {
      console.error('storefront/orders/:id/cancel POST error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not cancel this order right now.');
    }
  });

  return router;
}
