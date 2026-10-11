import { createHash } from 'node:crypto';
import {
  Prisma,
  type StorefrontOrder,
  type StorefrontPayment,
  type StorefrontPaymentStatus,
} from '@prisma/client';
import type { Router as ExpressRouterType } from 'express';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../../../lib/prisma';
import { requireAuth, requireRole } from '../../../lib/auth.middleware';
import { send200, send201, sendError } from '../../../lib/http';
import { hashOrderSecret, normalizeStorefrontPhone } from '../../storefront/storefront-orders.router';
import { DarajaMpesaAdapter, MpesaProviderError } from './daraja.adapter';
import {
  decryptMpesaConfiguration,
  encryptMpesaConfiguration,
  MpesaConfigurationError,
  type MpesaMerchantConfiguration,
} from './credential-store';
import type { MpesaCallbackResult } from './mpesa.contract';

const SETTING_KEY = 'integration.mpesa.credentials.v1';
const VERIFIED_SETTING_KEY = 'integration.mpesa.credentials.verified.v1';
const adapter = new DarajaMpesaAdapter();
const adminRoles = ['OWNER', 'MANAGER', 'SUPER_ADMIN'];
const activePaymentStatuses: StorefrontPaymentStatus[] = ['PENDING', 'UNKNOWN'];

const ConfigurationSchema = z.object({
  environment: z.enum(['sandbox', 'production']),
  shortcode: z.string().trim().regex(/^\d{5,10}$/),
  transactionType: z.enum([
    'CustomerPayBillOnline',
    'CustomerBuyGoodsOnline',
  ]),
  accountReference: z.string().trim().min(1).max(12),
  consumerKey: z.string().trim().min(8).max(256),
  consumerSecret: z.string().trim().min(8).max(256),
  passkey: z.string().trim().min(8).max(256),
});

const StartPaymentSchema = z.object({
  accessKey: z.string().uuid(),
  idempotencyKey: z.string().uuid(),
});

const PaymentStatusSchema = z.object({
  accessKey: z.string().uuid(),
});

const PaymentListSchema = z.object({
  status: z.enum(['PENDING', 'SUCCEEDED', 'FAILED', 'UNKNOWN']).optional(),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
});

class MpesaRouteError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

function callbackUrl(): string | null {
  const value = process.env.MPESA_CALLBACK_URL;
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' ? url.toString() : null;
  } catch {
    return null;
  }
}

async function storedConfiguration(businessId: string) {
  const setting = await prisma.businessSetting.findUnique({
    where: { businessId_key: { businessId, key: SETTING_KEY } },
    select: { value: true },
  });
  if (!setting) {
    throw new MpesaConfigurationError(
      'CREDENTIALS_NOT_CONFIGURED',
      'M-Pesa credentials have not been configured.',
    );
  }
  return decryptMpesaConfiguration(setting.value);
}

async function configStatus(businessId: string) {
  const [setting, verifiedSetting] = await Promise.all([
    prisma.businessSetting.findUnique({
      where: { businessId_key: { businessId, key: SETTING_KEY } },
      select: { value: true },
    }),
    prisma.businessSetting.findUnique({
      where: { businessId_key: { businessId, key: VERIFIED_SETTING_KEY } },
      select: { value: true },
    }),
  ]);
  let encryptionReady = false;
  try {
    if (setting) decryptMpesaConfiguration(setting.value);
    else {
      encryptMpesaConfiguration({
        environment: 'sandbox',
        shortcode: '12345',
        transactionType: 'CustomerPayBillOnline',
        accountReference: 'Order',
        consumerKey: 'placeholder-key',
        consumerSecret: 'placeholder-secret',
        passkey: 'placeholder-passkey',
      });
    }
    encryptionReady = true;
  } catch (error) {
    if (
      !(error instanceof MpesaConfigurationError) ||
      error.code !== 'ENCRYPTION_KEY_UNAVAILABLE'
    ) {
      throw error;
    }
  }
  let saved: MpesaMerchantConfiguration | null = null;
  if (setting && encryptionReady) saved = decryptMpesaConfiguration(setting.value);
  const verified = saved !== null && verifiedSetting?.value === true;
  return {
    configured: saved !== null,
    verified,
    encryptionReady,
    environment: saved?.environment ?? null,
    shortcode: saved?.shortcode ?? null,
    transactionType: saved?.transactionType ?? null,
    accountReference: saved?.accountReference ?? null,
    callbackUrl: callbackUrl(),
    paymentReady: Boolean(saved && verified && callbackUrl()),
  };
}

function paymentResponse(payment: {
  id: string;
  status: string;
  amount: Prisma.Decimal;
  phoneNumber: string;
  checkoutRequestId: string | null;
  mpesaReceipt: string | null;
  resultDescription: string | null;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: payment.id,
    status: payment.status,
    amount: Number(payment.amount),
    phoneNumber: payment.phoneNumber,
    receiptNumber: payment.mpesaReceipt,
    message: payment.resultDescription,
    createdAt: payment.createdAt,
    updatedAt: payment.updatedAt,
  };
}

function callbackFromPayload(payload: unknown): MpesaCallbackResult | null {
  return adapter.parseCallback(payload);
}

function amountAsWholeShillings(amount: Prisma.Decimal): string {
  if (!amount.isInteger() || amount.lte(0)) {
    throw new MpesaRouteError(
      422,
      'INVALID_PAYMENT_AMOUNT',
      'M-Pesa STK Push requires a whole-shilling order total.',
    );
  }
  return amount.toFixed(0);
}

async function createSaleForPaidOrder(
  tx: Prisma.TransactionClient,
  order: StorefrontOrder & {
    items: Array<{
      productId: string;
      productName: string;
      quantity: Prisma.Decimal;
      unitPrice: Prisma.Decimal;
      unitCost: Prisma.Decimal;
      vatRate: Prisma.Decimal;
      lineTotal: Prisma.Decimal;
    }>;
  },
  payment: StorefrontPayment,
  receiptNumber: string,
) {
  const currentCustomer = await tx.customer.findFirst({
    where: { businessId: order.businessId, phone: order.customerPhone },
  });
  const customer = currentCustomer
    ? await tx.customer.update({
        where: { id: currentCustomer.id },
        data: {
          fullName: order.customerName,
          ...(order.customerEmail ? { email: order.customerEmail } : {}),
        },
      })
    : await tx.customer.create({
        data: {
          businessId: order.businessId,
          fullName: order.customerName,
          phone: order.customerPhone,
          email: order.customerEmail,
        },
      });

  let vatCents = 0;
  let subtotalCents = 0;
  for (const item of order.items) {
    const lineTotalCents = item.lineTotal.mul(100).toDecimalPlaces(0).toNumber();
    const rate = item.vatRate.toNumber();
    const lineVatCents = Math.round((lineTotalCents * rate) / (1 + rate));
    vatCents += lineVatCents;
    subtotalCents += lineTotalCents - lineVatCents;
  }
  const subtotal = new Prisma.Decimal(subtotalCents).div(100);
  const vatAmount = new Prisma.Decimal(vatCents).div(100);

  const sale = await tx.sale.create({
    data: {
      businessId: order.businessId,
      receiptNumber,
      cashierId: null,
      customerId: customer.id,
      clientRef: `storefront-${order.id}`,
      idempotencyKey: `storefront-${order.id}`,
      status: 'COMPLETED',
      subtotal,
      vatAmount,
      total: order.total,
      costTotal: order.items.reduce(
        (sum, item) => sum.plus(item.unitCost.mul(item.quantity)),
        new Prisma.Decimal(0),
      ),
      offline: false,
      items: {
        create: order.items.map((item) => ({
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          unitCost: item.unitCost,
          vatRate: item.vatRate,
          lineTotal: item.lineTotal,
        })),
      },
      payments: {
        create: {
          method: 'MPESA',
          status: 'SUCCESS',
          amount: payment.amount,
          mpesaReceipt: receiptNumber,
          checkoutRequestId: payment.checkoutRequestId,
          idempotencyKey: `storefront-payment-${payment.id}`,
          resultCode: '0',
          resultDesc: 'Verified through Daraja STK Push query and callback.',
          reference: receiptNumber,
          settledAt: new Date(),
        },
      },
    },
  });
  return { sale, customer };
}

export async function verifyStorefrontMpesaPayment(
  businessId: string,
  paymentId: string,
): Promise<StorefrontPayment | null> {
  const payment = await prisma.storefrontPayment.findFirst({
    where: { id: paymentId, order: { businessId } },
    include: { order: { include: { items: true } } },
  });
  if (!payment || !payment.checkoutRequestId) return payment;
  if (!activePaymentStatuses.includes(payment.status)) return payment;

  let configuration: MpesaMerchantConfiguration;
  try {
    configuration = await storedConfiguration(businessId);
  } catch {
    return payment;
  }
  let providerResult;
  try {
    providerResult = await adapter.queryTransaction(configuration, {
      checkoutRequestId: payment.checkoutRequestId,
    });
  } catch {
    return payment;
  }

  if (providerResult.resultCode !== '0') {
    const correlatedFailureCallback =
      payment.callbackReceivedAt !== null &&
      payment.resultCode !== null &&
      payment.resultCode !== '0' &&
      (payment.merchantRequestId === null ||
        payment.callbackMerchantRequestId === payment.merchantRequestId);
    return prisma.storefrontPayment.update({
      where: { id: payment.id },
      data: {
        status: correlatedFailureCallback ? 'FAILED' : 'UNKNOWN',
        resultCode: providerResult.resultCode,
        resultDescription: correlatedFailureCallback
          ? providerResult.resultDescription
          : 'Daraja has not confirmed a final result. Reconcile again before taking further action.',
      },
    });
  }

  const callbackAmount = payment.callbackAmount;
  const callbackPhone = payment.callbackPhoneNumber
    ? normalizeStorefrontPhone(payment.callbackPhoneNumber)
    : null;
  if (
    !callbackAmount ||
    !callbackPhone ||
    !payment.callbackReceiptNumber ||
    payment.resultCode !== '0' ||
    !payment.callbackReceivedAt ||
    callbackAmount.comparedTo(payment.amount) !== 0 ||
    callbackPhone !== normalizeStorefrontPhone(payment.phoneNumber) ||
    (payment.merchantRequestId !== null &&
      payment.callbackMerchantRequestId !== payment.merchantRequestId)
  ) {
    return prisma.storefrontPayment.update({
      where: { id: payment.id },
      data: {
        status: 'UNKNOWN',
        resultCode: 'CALLBACK_MISMATCH',
        resultDescription:
          'Daraja reports success but callback amount, phone number, or receipt could not be verified. Review before fulfilment.',
      },
    });
  }

  try {
    return await prisma.$transaction(async (tx) => {
      await tx.$queryRaw`
        SELECT "id" FROM "storefront_orders"
        WHERE "id" = ${payment.orderId}::uuid
          AND "businessId" = ${businessId}::uuid
        FOR UPDATE
      `;
      const current = await tx.storefrontPayment.findUniqueOrThrow({
        where: { id: payment.id },
      });
      if (!activePaymentStatuses.includes(current.status)) return current;
      const order = await tx.storefrontOrder.findFirstOrThrow({
        where: { id: payment.orderId, businessId },
        include: { items: true },
      });
      if (order.status !== 'AWAITING_PAYMENT') {
        return tx.storefrontPayment.update({
          where: { id: payment.id },
          data: {
            status: 'UNKNOWN',
            resultCode: 'ORDER_NOT_PAYABLE',
            resultDescription:
              'Payment was verified after the order became unavailable. Staff review is required before fulfilment.',
          },
        });
      }
      const alreadyRecorded = await tx.sale.findUnique({
        where: { idempotencyKey: `storefront-${order.id}` },
        select: { id: true },
      });
      if (alreadyRecorded) {
        return tx.storefrontPayment.update({
          where: { id: payment.id },
          data: {
            status: 'SUCCEEDED',
            saleId: alreadyRecorded.id,
            mpesaReceipt: payment.callbackReceiptNumber,
            verifiedAt: new Date(),
          },
        });
      }
      const { sale } = await createSaleForPaidOrder(
        tx,
        order,
        current,
        payment.callbackReceiptNumber!,
      );
      await tx.storefrontPayment.update({
        where: { id: payment.id },
        data: {
          status: 'SUCCEEDED',
          saleId: sale.id,
          mpesaReceipt: payment.callbackReceiptNumber,
          resultCode: providerResult.resultCode,
          resultDescription: providerResult.resultDescription,
          verifiedAt: new Date(),
        },
      });
      await tx.storefrontOrder.update({
        where: { id: order.id },
        data: { status: 'PAID', saleId: sale.id },
      });
      await tx.storefrontOrderEvent.create({
        data: {
          orderId: order.id,
          fromStatus: 'AWAITING_PAYMENT',
          toStatus: 'PAID',
          detail: `M-Pesa payment verified. POS sale ${sale.receiptNumber} was recorded.`,
        },
      });
      return tx.storefrontPayment.findUniqueOrThrow({
        where: { id: payment.id },
      });
    });
  } catch (error) {
    if (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === 'P2002'
    ) {
      return prisma.storefrontPayment.update({
        where: { id: payment.id },
        data: {
          status: 'UNKNOWN',
          resultCode: 'DUPLICATE_RECEIPT',
          resultDescription:
            'The provider receipt is already attached to another payment. Review is required.',
        },
      });
    }
    throw error;
  }
}

export function mpesaRouter(businessId: string): ExpressRouterType {
  const router = Router();

  router.post('/callback', async (req, res) => {
    const callback = callbackFromPayload(req.body);
    if (!callback) {
      return res.status(503).json({
        ResultCode: 1,
        ResultDesc: 'Callback could not be parsed and recorded.',
      });
    }
    try {
      const payment = await prisma.storefrontPayment.findFirst({
        where: {
          checkoutRequestId: callback.checkoutRequestId,
          order: { businessId },
        },
      });
      if (!payment) {
        console.warn('Unmatched M-Pesa callback received.');
        return res.status(503).json({
          ResultCode: 1,
          ResultDesc: 'Callback could not be correlated to a recorded payment.',
        });
      }
      const recorded = await prisma.storefrontPayment.updateMany({
        where: {
          id: payment.id,
          status: { in: [...activePaymentStatuses] },
        },
        data: {
          callbackReceivedAt: new Date(),
          callbackAmount: callback.amount
            ? new Prisma.Decimal(callback.amount)
            : null,
          callbackPhoneNumber: callback.phoneNumber ?? null,
          callbackMerchantRequestId: callback.merchantRequestId ?? null,
          callbackReceiptNumber: callback.receiptNumber ?? null,
          resultCode: callback.resultCode,
          resultDescription: callback.resultDescription,
          status: 'UNKNOWN',
        },
      });
      if (recorded.count === 0) {
        return res.status(200).json({
          ResultCode: 0,
          ResultDesc: 'Callback already processed.',
        });
      }
      res.status(200).json({
        ResultCode: 0,
        ResultDesc: 'Callback received for verification.',
      });
      setImmediate(() => {
        void verifyStorefrontMpesaPayment(businessId, payment.id).catch(
          (error: unknown) => {
            console.error('M-Pesa callback verification failed:', error);
          },
        );
      });
      return;
    } catch (error) {
      console.error('M-Pesa callback persistence failed:', error);
      return res.status(503).json({
        ResultCode: 1,
        ResultDesc: 'Callback could not be recorded.',
      });
    }
  });

  router.get(
    '/availability',
    async (_req, res) => {
      try {
        const status = await configStatus(businessId);
        return send200(res, {
          data: { pickupPaymentsEnabled: status.paymentReady },
        });
      } catch (error) {
        console.error('M-Pesa availability error:', error);
        return sendError(
          res,
          503,
          'PAYMENT_STATUS_UNAVAILABLE',
          'Pickup payment availability could not be checked.',
        );
      }
    },
  );

  router.get(
    '/config',
    requireAuth,
    requireRole(...adminRoles),
    async (_req, res) => {
      try {
        return send200(res, { data: await configStatus(businessId) });
      } catch (error) {
        console.error('M-Pesa config status error:', error);
        return sendError(
          res,
          500,
          'SERVER_ERROR',
          'Could not load M-Pesa configuration status.',
        );
      }
    },
  );

  router.put(
    '/config',
    requireAuth,
    requireRole(...adminRoles),
    async (req, res) => {
      const parsed = ConfigurationSchema.safeParse(req.body);
      if (!parsed.success) {
        return sendError(
          res,
          422,
          'INVALID_CONFIGURATION',
          parsed.error.issues[0]?.message ?? 'Check the M-Pesa configuration.',
        );
      }
      try {
        const encrypted = { ...encryptMpesaConfiguration(parsed.data) };
        await prisma.$transaction(async (tx) => {
          await tx.businessSetting.upsert({
            where: { businessId_key: { businessId, key: SETTING_KEY } },
            update: { value: encrypted },
            create: { businessId, key: SETTING_KEY, value: encrypted },
          });
          await tx.businessSetting.upsert({
            where: {
              businessId_key: { businessId, key: VERIFIED_SETTING_KEY },
            },
            update: { value: false },
            create: {
              businessId,
              key: VERIFIED_SETTING_KEY,
              value: false,
            },
          });
        });
        return send200(res, { data: await configStatus(businessId) });
      } catch (error) {
        if (error instanceof MpesaConfigurationError) {
          return sendError(res, 503, error.code, error.message);
        }
        console.error('M-Pesa config save error:', error);
        return sendError(
          res,
          500,
          'SERVER_ERROR',
          'Could not securely save M-Pesa configuration.',
        );
      }
    },
  );

  router.post(
    '/test',
    requireAuth,
    requireRole(...adminRoles),
    async (_req, res) => {
      try {
        const configuration = await storedConfiguration(businessId);
        await adapter.testConnection(configuration);
        const verified = await prisma.$transaction(async (tx) => {
          await tx.$queryRaw`
            SELECT "id" FROM "business_settings"
            WHERE "businessId" = ${businessId}::uuid AND "key" = ${SETTING_KEY}
            FOR UPDATE
          `;
          const currentSetting = await tx.businessSetting.findUnique({
            where: { businessId_key: { businessId, key: SETTING_KEY } },
            select: { value: true },
          });
          if (
            !currentSetting ||
            JSON.stringify(decryptMpesaConfiguration(currentSetting.value)) !==
              JSON.stringify(configuration)
          ) {
            return false;
          }
          await tx.businessSetting.upsert({
            where: {
              businessId_key: { businessId, key: VERIFIED_SETTING_KEY },
            },
            update: { value: true },
            create: {
              businessId,
              key: VERIFIED_SETTING_KEY,
              value: true,
            },
          });
          return true;
        });
        if (!verified) {
          return sendError(
            res,
            409,
            'CREDENTIALS_CHANGED',
            'M-Pesa credentials changed during the connection test. Test the saved credentials again.',
          );
        }
        return send200(res, { data: { connected: true } });
      } catch (error) {
        if (error instanceof MpesaConfigurationError) {
          return sendError(res, 409, error.code, error.message);
        }
        return sendError(
          res,
          502,
          'MPESA_CONNECTION_FAILED',
          error instanceof MpesaProviderError
            ? error.message
            : 'Daraja connection could not be verified.',
        );
      }
    },
  );

  router.get(
    '/transactions',
    requireAuth,
    requireRole(...adminRoles),
    async (req, res) => {
      const parsed = PaymentListSchema.safeParse(req.query);
      if (!parsed.success) {
        return sendError(res, 422, 'INVALID_QUERY', 'Check the payment filters.');
      }
      try {
        const where = {
          order: { businessId },
          ...(parsed.data.status ? { status: parsed.data.status } : {}),
        };
        const [payments, total] = await Promise.all([
          prisma.storefrontPayment.findMany({
            where,
            include: {
              order: {
                select: {
                  id: true,
                  orderNumber: true,
                  customerName: true,
                  fulfillmentMethod: true,
                },
              },
            },
            orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
            skip: (parsed.data.page - 1) * parsed.data.limit,
            take: parsed.data.limit,
          }),
          prisma.storefrontPayment.count({ where }),
        ]);
        return send200(res, {
          data: payments.map((payment) => ({
            ...paymentResponse(payment),
            order: payment.order,
          })),
          meta: {
            total,
            page: parsed.data.page,
            limit: parsed.data.limit,
          },
        });
      } catch (error) {
        console.error('M-Pesa transactions list error:', error);
        return sendError(res, 500, 'SERVER_ERROR', 'Could not load M-Pesa transactions.');
      }
    },
  );

  router.post(
    '/transactions/:id/reconcile',
    requireAuth,
    requireRole(...adminRoles),
    async (req, res) => {
      try {
        const payment = await verifyStorefrontMpesaPayment(businessId, req.params['id'] ?? '');
        if (!payment) {
          return sendError(res, 404, 'NOT_FOUND', 'M-Pesa transaction not found.');
        }
        return send200(res, { data: paymentResponse(payment) });
      } catch (error) {
        console.error('M-Pesa transaction reconciliation error:', error);
        return sendError(
          res,
          500,
          'SERVER_ERROR',
          'Could not reconcile this M-Pesa transaction.',
        );
      }
    },
  );

  router.post('/orders/:id', async (req, res) => {
    const body = StartPaymentSchema.safeParse(req.body);
    if (!body.success) {
      return sendError(res, 422, 'INVALID_PAYMENT_REQUEST', 'Check the payment request and try again.');
    }
    try {
      const orderId = req.params['id'] ?? '';
      const keyHash = hashOrderSecret(body.data.accessKey);
      const order = await prisma.storefrontOrder.findFirst({
        where: {
          id: orderId,
          businessId,
          idempotencyKeyHash: keyHash,
        },
        include: { items: true },
      });
      if (!order) return sendError(res, 404, 'NOT_FOUND', 'Order not found.');
      if (order.status !== 'AWAITING_PAYMENT') {
        return sendError(res, 409, 'ORDER_NOT_PAYABLE', 'This order is no longer awaiting payment.');
      }
      if (order.expiresAt <= new Date()) {
        return sendError(res, 409, 'ORDER_EXPIRED', 'The order stock hold has expired. Start a new checkout.');
      }
      if (order.fulfillmentMethod !== 'PICKUP') {
        return sendError(
          res,
          409,
          'DELIVERY_FEE_UNCONFIRMED',
          'Online M-Pesa payment is available for pickup orders only. The shop must confirm delivery pricing first.',
        );
      }
      const callback = callbackUrl();
      if (!callback) {
        return sendError(
          res,
          503,
          'CALLBACK_URL_UNAVAILABLE',
          'M-Pesa payment is not ready because a public HTTPS callback URL is not configured.',
        );
      }
      const configuration = await storedConfiguration(businessId);
      const amount = order.total.plus(order.deliveryFee ?? 0);
      const amountText = amountAsWholeShillings(amount);
      const key = sha256(`${order.id}:${body.data.idempotencyKey}`);
      const requestHash = sha256(
        JSON.stringify({
          orderId: order.id,
          amount: amountText,
          phone: order.customerPhone,
        }),
      );
      const reserved = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw`
          SELECT "id" FROM "storefront_orders"
          WHERE "id" = ${order.id}::uuid AND "businessId" = ${businessId}::uuid
          FOR UPDATE
        `;
        const replay = await tx.storefrontPayment.findUnique({
          where: { idempotencyKeyHash: key },
        });
        if (replay) {
          if (replay.requestHash !== requestHash) {
            throw new MpesaRouteError(
              409,
              'IDEMPOTENCY_KEY_REUSED',
              'This payment retry key belongs to different payment details.',
            );
          }
          return { payment: replay, replay: true };
        }
        const current = await tx.storefrontOrder.findFirstOrThrow({
          where: { id: order.id, businessId },
          include: { payments: { where: { status: { in: [...activePaymentStatuses] } } } },
        });
        if (current.status !== 'AWAITING_PAYMENT' || current.expiresAt <= new Date()) {
          throw new MpesaRouteError(
            409,
            'ORDER_NOT_PAYABLE',
            'This order is no longer available for payment.',
          );
        }
        if (current.payments.length > 0) {
          throw new MpesaRouteError(
            409,
            'PAYMENT_IN_PROGRESS',
            'A payment is already awaiting confirmation. Refresh its status before retrying.',
          );
        }
        const payment = await tx.storefrontPayment.create({
          data: {
            orderId: current.id,
            idempotencyKeyHash: key,
            requestHash,
            amount,
            phoneNumber: normalizeStorefrontPhone(current.customerPhone),
            status: 'PENDING',
          },
        });
        return { payment, replay: false };
      });
      if (reserved.replay || reserved.payment.checkoutRequestId) {
        return send200(res, { data: paymentResponse(reserved.payment) });
      }

      try {
        const result = await adapter.initiateStkPush(configuration, {
          idempotencyKey: body.data.idempotencyKey,
          amount: amountText,
          phoneNumber: reserved.payment.phoneNumber,
          accountReference: `${configuration.accountReference}-${order.orderNumber.slice(-6)}`.slice(0, 12),
          transactionDescription: `Order ${order.orderNumber.slice(-8)}`,
          callbackUrl: callback,
        });
        const payment = await prisma.storefrontPayment.update({
          where: { id: reserved.payment.id },
          data: {
            status: result.responseCode === '0' ? 'PENDING' : 'FAILED',
            checkoutRequestId: result.checkoutRequestId,
            merchantRequestId: result.merchantRequestId,
            resultCode: result.responseCode,
            resultDescription: result.customerMessage ?? result.responseDescription,
          },
        });
        return send201(res, { data: paymentResponse(payment) });
      } catch (error) {
        const payment = await prisma.storefrontPayment.update({
          where: { id: reserved.payment.id },
          data: {
            status:
              error instanceof MpesaProviderError && !error.retryable
                ? 'FAILED'
                : 'UNKNOWN',
            resultCode:
              error instanceof MpesaProviderError ? error.providerCode ?? null : null,
            resultDescription:
              error instanceof MpesaProviderError
                ? error.message
                : 'Daraja response was interrupted; the payment status must be reconciled.',
          },
        });
        return send200(res, { data: paymentResponse(payment) });
      }
    } catch (error) {
      if (error instanceof MpesaRouteError) {
        return sendError(res, error.status, error.code, error.message);
      }
      if (error instanceof MpesaConfigurationError) {
        return sendError(res, 409, error.code, error.message);
      }
      console.error('M-Pesa payment initiation error:', error);
      return sendError(
        res,
        500,
        'SERVER_ERROR',
        'Could not start this M-Pesa payment. Do not retry until you refresh payment status.',
      );
    }
  });

  router.post('/orders/:id/status', async (req, res) => {
    const body = PaymentStatusSchema.safeParse(req.body);
    if (!body.success) {
      return sendError(res, 422, 'INVALID_ORDER_ACCESS', 'This order link is invalid.');
    }
    try {
      const paymentId = req.query['paymentId'];
      if (typeof paymentId !== 'string') {
        return sendError(res, 422, 'INVALID_PAYMENT', 'This payment reference is invalid.');
      }
      const payment = await prisma.storefrontPayment.findFirst({
        where: {
          id: paymentId,
          order: {
            id: req.params['id'],
            businessId,
            idempotencyKeyHash: hashOrderSecret(body.data.accessKey),
          },
        },
      });
      if (!payment) return sendError(res, 404, 'NOT_FOUND', 'Payment not found.');
      if (activePaymentStatuses.includes(payment.status)) {
        const refreshed = await verifyStorefrontMpesaPayment(businessId, payment.id);
        return send200(res, { data: paymentResponse(refreshed ?? payment) });
      }
      return send200(res, { data: paymentResponse(payment) });
    } catch (error) {
      console.error('M-Pesa customer payment status error:', error);
      return sendError(
        res,
        500,
        'SERVER_ERROR',
        'Could not refresh this payment status.',
      );
    }
  });

  return router;
}
