/**
 * Business module — settings, profile, and summary reporting.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { parseBody, send200, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const StorefrontSettingsSchema = z.object({
  storeName: z.string().trim().min(1).max(200),
  description: z.string().max(2000),
  phone: z.string().max(40),
  email: z.union([z.string().email(), z.literal('')]),
  address: z.string().max(300),
  county: z.string().max(100),
  logoUrl: z.union([
    z.string().url().refine((value) => value.startsWith('https://')),
    z.literal(''),
  ]),
  openingHours: z.string().max(2000),
  deliveryEnabled: z.boolean(),
  deliveryDetails: z.string().max(3000),
  pickupEnabled: z.boolean(),
  pickupDetails: z.string().max(3000),
  policies: z.object({
    delivery: z.string().max(8000),
    returns: z.string().max(8000),
    privacy: z.string().max(8000),
    terms: z.string().max(8000),
  }),
});

type StorefrontSettings = z.infer<typeof StorefrontSettingsSchema>;
const storefrontSettingKey = 'storefront_profile';

const UpdateBusinessSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  phone: z.string().optional(),
  email: z.string().email().optional(),
  address: z.string().optional(),
  county: z.string().optional(),
  logoUrl: z.string().url().optional(),
  vatRate: z.number().min(0).max(1).optional(),
  currency: z.string().length(3).optional(),
});

const UpsertSettingSchema = z.object({
  value: z.unknown(),
});

export function businessRouter(businessId: string): Router {
  const router = ExpressRouter();

  // Public storefront profile contains only information explicitly configured
  // for publication; internal POS contact details remain private by default.
  router.get('/storefront', async (_req, res) => {
    try {
      const business = await prisma.business.findUniqueOrThrow({
        where: { id: businessId },
        include: {
          settings: { where: { key: storefrontSettingKey }, take: 1 },
        },
      });
      const profile = readStorefrontSettings(
        business.name,
        business.settings[0]?.value,
      );
      res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=60');
      return send200(res, { data: profile });
    } catch (err) {
      console.error('business/storefront error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch storefront profile.');
    }
  });

  // GET /business/storefront/settings
  router.get(
    '/storefront/settings',
    requireAuth,
    requireRole('OWNER', 'MANAGER'),
    async (_req, res) => {
      try {
        const business = await prisma.business.findUniqueOrThrow({
          where: { id: businessId },
          include: {
            settings: { where: { key: storefrontSettingKey }, take: 1 },
          },
        });
        return send200(res, {
          data: readStorefrontSettings(
            business.name,
            business.settings[0]?.value,
          ),
        });
      } catch (err) {
        console.error('business/storefront settings get error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch storefront settings.');
      }
    },
  );

  // PUT /business/storefront/settings
  router.put(
    '/storefront/settings',
    requireAuth,
    requireRole('OWNER', 'MANAGER'),
    async (req, res) => {
      const body = parseBody(StorefrontSettingsSchema, req, res);
      if (!body) return;
      try {
        const value: Prisma.InputJsonObject = {
          ...body,
          policies: body.policies,
        };
        await prisma.businessSetting.upsert({
          where: {
            businessId_key: { businessId, key: storefrontSettingKey },
          },
          update: { value },
          create: { businessId, key: storefrontSettingKey, value },
        });
        return send200(res, { data: body });
      } catch (err) {
        console.error('business/storefront settings update error:', err);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to update storefront settings.');
      }
    },
  );

  // GET /business
  router.get('/', requireAuth, async (req, res) => {
    try {
      const biz = await prisma.business.findUniqueOrThrow({
        where: { id: businessId },
        include: { settings: true },
      });
      return send200(res, {
        id: biz.id,
        name: biz.name,
        slug: biz.slug,
        phone: biz.phone,
        email: biz.email,
        address: biz.address,
        county: biz.county,
        logoUrl: biz.logoUrl,
        vatRate: Number(biz.vatRate),
        currency: biz.currency,
        settings: Object.fromEntries(biz.settings.map((s) => [s.key, s.value])),
      });
    } catch (err) {
      console.error('business/get error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch business profile.');
    }
  });

  // PATCH /business
  router.patch('/', requireAuth, requireRole('OWNER'), async (req, res) => {
    const body = parseBody(UpdateBusinessSchema, req, res);
    if (!body) return;
    try {
      const biz = await prisma.business.update({ where: { id: businessId }, data: body });
      return send200(res, biz);
    } catch (err) {
      console.error('business/update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update business profile.');
    }
  });

  // PUT /business/settings/:key
  router.put('/settings/:key', requireAuth, requireRole('OWNER'), async (req, res) => {
    const key = req.params.key;
    if (!key) return sendError(res, 400, 'BAD_REQUEST', 'Missing setting key.');
    const body = parseBody(UpsertSettingSchema, req, res);
    if (!body) return;
    try {
      const setting = await prisma.businessSetting.upsert({
        where: { businessId_key: { businessId, key } },
        update: { value: body.value as any },
        create: { businessId, key, value: body.value as any },
      });
      return send200(res, setting);
    } catch (err) {
      console.error('business/settings/upsert error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update setting.');
    }
  });

  // GET /business/reports/dashboard
  router.get('/reports/dashboard', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    try {
      const now = new Date();
      const todayStart = new Date(now); todayStart.setHours(0, 0, 0, 0);
      const weekStart = new Date(todayStart); weekStart.setDate(weekStart.getDate() - 7);
      const monthStart = new Date(todayStart); monthStart.setDate(1);

      const [
        todaySales,
        weekSales,
        monthSales,
        lowStockCount,
        outstandingCredit,
        topProducts,
      ] = await Promise.all([
        prisma.sale.aggregate({
          where: { businessId, status: 'COMPLETED', createdAt: { gte: todayStart } },
          _sum: { total: true },
          _count: true,
        }),
        prisma.sale.aggregate({
          where: { businessId, status: 'COMPLETED', createdAt: { gte: weekStart } },
          _sum: { total: true },
          _count: true,
        }),
        prisma.sale.aggregate({
          where: { businessId, status: 'COMPLETED', createdAt: { gte: monthStart } },
          _sum: { total: true },
          _count: true,
        }),
        prisma.product.count({
          where: { businessId, active: true, stock: { lte: prisma.product.fields.lowStockThreshold } },
        }),
        prisma.customer.aggregate({
          where: { businessId, balance: { gt: 0 } },
          _sum: { balance: true },
          _count: true,
        }),
        // Top 5 products by revenue this month
        prisma.saleItem.groupBy({
          by: ['productId'],
          where: { sale: { businessId, status: 'COMPLETED', createdAt: { gte: monthStart } } },
          _sum: { lineTotal: true, quantity: true },
          orderBy: { _sum: { lineTotal: 'desc' } },
          take: 5,
        }),
      ]);

      // Enrich top products with names
      const productIds = topProducts.map((p) => p.productId);
      const products = await prisma.product.findMany({
        where: { id: { in: productIds } },
        select: { id: true, name: true },
      });
      const productMap = Object.fromEntries(products.map((p) => [p.id, p.name]));

      // Last 7 days daily breakdown
      const last7 = await prisma.sale.findMany({
        where: { businessId, status: 'COMPLETED', createdAt: { gte: weekStart } },
        select: { total: true, createdAt: true },
      });

      const dailyMap: Record<string, number> = {};
      for (const s of last7) {
        const key = s.createdAt.toISOString().slice(0, 10);
        dailyMap[key] = (dailyMap[key] ?? 0) + Number(s.total);
      }

      const dailySeries = Array.from({ length: 7 }, (_, i) => {
        const d = new Date(todayStart);
        d.setDate(d.getDate() - (6 - i));
        const key = d.toISOString().slice(0, 10);
        return { date: key, total: dailyMap[key] ?? 0 };
      });

      return send200(res, {
        today: { total: Number(todaySales._sum.total ?? 0), count: todaySales._count },
        week: { total: Number(weekSales._sum.total ?? 0), count: weekSales._count },
        month: { total: Number(monthSales._sum.total ?? 0), count: monthSales._count },
        lowStockCount,
        outstandingCredit: {
          total: Number(outstandingCredit._sum.balance ?? 0),
          customers: outstandingCredit._count,
        },
        topProducts: topProducts.map((p) => ({
          productId: p.productId,
          name: productMap[p.productId] ?? 'Unknown',
          revenue: Number(p._sum.lineTotal ?? 0),
          quantity: Number(p._sum.quantity ?? 0),
        })),
        dailySeries,
      });
    } catch (err) {
      console.error('business/reports/dashboard error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to generate dashboard report.');
    }
  });

  return router;
}

function readStorefrontSettings(
  businessName: string,
  savedValue: Prisma.JsonValue | undefined,
): StorefrontSettings {
  const defaults: StorefrontSettings = {
    storeName: businessName,
    description: '',
    phone: '',
    email: '',
    address: '',
    county: '',
    logoUrl: '',
    openingHours: '',
    deliveryEnabled: false,
    deliveryDetails: '',
    pickupEnabled: false,
    pickupDetails: '',
    policies: { delivery: '', returns: '', privacy: '', terms: '' },
  };
  if (savedValue === undefined) return defaults;

  const result = StorefrontSettingsSchema.safeParse(savedValue);
  if (!result.success) {
    throw new Error('Saved storefront settings have an invalid shape.');
  }
  return result.data;
}
