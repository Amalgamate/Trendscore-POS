/**
 * Products module — catalog CRUD and barcode lookup.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import type { StockMovementType } from '@prisma/client';
import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth } from '../../lib/auth.middleware';

const ListProductsQuerySchema = z.object({
  category: z.string().optional(),
  search: z.string().optional(),
  lowStock: z.enum(['true', 'false']).optional(),
  active: z.enum(['true', 'false', 'all']).optional().default('true'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(200).default(100),
});

const CreateProductSchema = z.object({
  name: z.string().min(1).max(200),
  sku: z.string().max(100).optional(),
  barcode: z.string().max(100).optional(),
  categoryId: z.string().uuid().optional(),
  salePrice: z.number().positive(),
  costPrice: z.number().nonnegative().default(0),
  vatRate: z.number().min(0).max(1).default(0.16),
  unit: z.string().default('pc'),
  initialStock: z.number().nonnegative().default(0),
  lowStockThreshold: z.number().nonnegative().default(5),
});

const UpdateProductSchema = CreateProductSchema.partial()
  .omit({ initialStock: true })
  .extend({ active: z.boolean().optional() });

const ImportProductsSchema = z.object({
  products: z.array(z.object({
    name: z.string().min(1).max(200),
    sku: z.string().min(1).max(100),
    barcode: z.string().max(100).optional(),
    category: z.string().min(1).max(100),
    salePrice: z.number().positive(),
    costPrice: z.number().nonnegative().default(0),
    vatRate: z.number().min(0).max(1).default(0.16),
    unit: z.string().default('pc'),
    initialStock: z.number().nonnegative().default(0),
    lowStockThreshold: z.number().nonnegative().default(5),
  })).min(1).max(500),
});

const StockAdjustSchema = z.object({
  delta: z.number().int(),
  type: z.enum(['ADJUSTMENT_IN', 'ADJUSTMENT_OUT', 'DAMAGE', 'EXPIRY', 'PURCHASE']),
  reason: z.string().min(1).max(500),
});

export function productsRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /products
  router.get('/', requireAuth, async (req, res) => {
    const query = parseQuery(ListProductsQuerySchema, req, res);
    if (!query) return;

    const page = query.page ?? 1;
    const limit = query.limit ?? 100;

    const where: Prisma.ProductWhereInput = {
      businessId,
      ...(query.active === 'all' ? {} : { active: query.active === 'true' }),
      ...(query.category ? { category: { name: { equals: query.category, mode: 'insensitive' as const } } } : {}),
      ...(query.search
        ? {
            OR: [
              { name: { contains: query.search, mode: 'insensitive' as const } },
              { sku: { contains: query.search, mode: 'insensitive' as const } },
              { barcode: { contains: query.search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
      ...(query.lowStock === 'true' ? { stock: { lte: prisma.product.fields.lowStockThreshold } } : {}),
    };

    try {
      const [products, total] = await Promise.all([
        prisma.product.findMany({
          where,
          include: { category: { select: { id: true, name: true, colorHex: true } } },
          orderBy: [{ category: { sortOrder: 'asc' } }, { name: 'asc' }],
          skip: (page - 1) * limit,
          take: limit,
        }),
        prisma.product.count({ where }),
      ]);

      return send200(res, {
        data: products.map(mapProduct),
        meta: { total, page, limit, pages: Math.ceil(total / limit) },
      });
    } catch (err) {
      console.error('products/list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch products.');
    }
  });

  // GET /products/barcode/:barcode
  router.get('/barcode/:barcode', requireAuth, async (req, res) => {
    try {
      const product = await prisma.product.findFirst({
        where: { barcode: req.params.barcode, businessId, active: true },
        include: { category: { select: { id: true, name: true, colorHex: true } } },
      });
      if (!product) return sendError(res, 404, 'NOT_FOUND', 'No active product with that barcode.');
      return send200(res, mapProduct(product));
    } catch (err) {
      console.error('products/barcode error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch product.');
    }
  });

  // GET /products/:id
  router.get('/:id', requireAuth, async (req, res) => {
    try {
      const product = await prisma.product.findFirst({
        where: { id: req.params.id, businessId },
        include: { category: { select: { id: true, name: true, colorHex: true } } },
      });
      if (!product) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      return send200(res, mapProduct(product));
    } catch (err) {
      console.error('products/get error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch product.');
    }
  });

  // POST /products
  router.post('/', requireAuth, async (req, res) => {
    const body = parseBody(CreateProductSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    const initialStock = body.initialStock ?? 0;
    const costPrice = body.costPrice ?? 0;
    const vatRate = body.vatRate ?? 0.16;
    const unit = body.unit ?? 'pc';
    const lowStockThreshold = body.lowStockThreshold ?? 5;

    try {
      const product = await prisma.$transaction(async (tx) => {
        const p = await tx.product.create({
          data: {
            businessId,
            name: body.name,
            sku: body.sku,
            barcode: body.barcode,
            categoryId: body.categoryId,
            salePrice: body.salePrice,
            costPrice,
            vatRate,
            unit,
            stock: initialStock,
            lowStockThreshold,
          },
          include: { category: { select: { id: true, name: true, colorHex: true } } },
        });

        if (initialStock > 0) {
          await tx.stockMovement.create({
            data: {
              businessId,
              productId: p.id,
              createdById: auth.userId,
              type: 'PURCHASE',
              quantity: initialStock,
              balanceAfter: initialStock,
              note: 'Opening stock',
            },
          });
        }
        return p;
      });

      return send201(res, mapProduct(product));
    } catch (err: unknown) {
      if (isUniqueConstraintError(err)) {
        return sendError(res, 409, 'DUPLICATE_SKU', 'A product with that SKU or barcode already exists.');
      }
      console.error('products/create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create product.');
    }
  });

  // POST /products/import — create CSV rows and their opening stock in one
  // business-scoped transaction, so a failed batch cannot leave half an import.
  router.post('/import', requireAuth, async (req, res) => {
    const body = parseBody(ImportProductsSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    try {
      const products = await prisma.$transaction(async (tx) => {
        const created = [];
        for (const row of body.products) {
          const initialStock = row.initialStock ?? 0;
          const costPrice = row.costPrice ?? 0;
          const vatRate = row.vatRate ?? 0.16;
          const unit = row.unit ?? 'pc';
          const lowStockThreshold = row.lowStockThreshold ?? 5;
          const category = await tx.category.upsert({
            where: { businessId_name: { businessId, name: row.category } },
            update: {},
            create: { businessId, name: row.category },
          });
          const product = await tx.product.create({
            data: {
              businessId,
              categoryId: category.id,
              name: row.name,
              sku: row.sku,
              barcode: row.barcode,
              salePrice: row.salePrice,
              costPrice,
              vatRate,
              unit,
              stock: initialStock,
              lowStockThreshold,
            },
            include: { category: { select: { id: true, name: true, colorHex: true } } },
          });
          if (initialStock > 0) {
            await tx.stockMovement.create({
              data: {
                businessId,
                productId: product.id,
                createdById: auth.userId,
                type: 'PURCHASE',
                quantity: initialStock,
                balanceAfter: initialStock,
                note: 'Opening stock from CSV import',
              },
            });
          }
          created.push(mapProduct(product));
        }
        return created;
      });
      return send201(res, { data: products });
    } catch (err: unknown) {
      if (isUniqueConstraintError(err)) {
        return sendError(res, 409, 'DUPLICATE_SKU', 'A product with that SKU or barcode already exists. No products were imported.');
      }
      console.error('products/import error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to import products. No products were imported.');
    }
  });

  // PATCH /products/:id
  router.patch('/:id', requireAuth, async (req, res) => {
    const body = parseBody(UpdateProductSchema, req, res);
    if (!body) return;

    try {
      // Ownership check — ensure this product belongs to the routed business.
      const existing = await prisma.product.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true },
      });
      if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');

      const product = await prisma.product.update({
        where: { id: existing.id },
        data: body,
        include: { category: { select: { id: true, name: true, colorHex: true } } },
      });
      return send200(res, mapProduct(product));
    } catch (err: unknown) {
      if (isNotFoundError(err)) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      console.error('products/update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update product.');
    }
  });

  // DELETE /products/:id — deactivate, preserving references from receipts,
  // stock movements, and historical reports.
  router.delete('/:id', requireAuth, async (req, res) => {
    try {
      const existing = await prisma.product.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true, active: true },
      });
      if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      if (!existing.active) return send200(res, { id: existing.id, active: false });

      const product = await prisma.product.update({
        where: { id: existing.id },
        data: { active: false },
        select: { id: true, active: true },
      });
      return send200(res, product);
    } catch (err) {
      console.error('products/deactivate error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to deactivate product.');
    }
  });

  // POST /products/:id/adjust-stock
  router.post('/:id/adjust-stock', requireAuth, async (req, res) => {
    const body = parseBody(StockAdjustSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    const productId = req.params.id;
    if (!productId) return sendError(res, 400, 'BAD_REQUEST', 'Missing product ID.');

    try {
      const result = await prisma.$transaction(async (tx) => {
        const product = await tx.product.findFirstOrThrow({ where: { id: productId, businessId } });
        const newStock = Number(product.stock) + body.delta;

        if (newStock < 0) {
          throw new Error('STOCK_NEGATIVE');
        }

        await tx.product.update({
          where: { id: productId },
          data: { stock: newStock },
        });

        await tx.stockMovement.create({
          data: {
            businessId,
            productId,
            createdById: auth.userId,
            type: body.type as StockMovementType,
            quantity: body.delta,
            balanceAfter: newStock,
            note: body.reason,
          },
        });

        return { productId, newStock, delta: body.delta };
      });

      return send200(res, result);
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'STOCK_NEGATIVE') {
        return sendError(res, 422, 'STOCK_NEGATIVE', 'Adjustment would drive stock below zero.');
      }
      console.error('products/adjust-stock error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to adjust stock.');
    }
  });

  return router;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function mapProduct(p: any) {
  return {
    id: p.id,
    name: p.name,
    sku: p.sku,
    barcode: p.barcode,
    category: p.category,
    salePrice: Number(p.salePrice),
    costPrice: Number(p.costPrice),
    vatRate: Number(p.vatRate),
    unit: p.unit,
    stock: Number(p.stock),
    lowStockThreshold: Number(p.lowStockThreshold),
    active: p.active,
    varianceFlag: p.varianceFlag,
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function isUniqueConstraintError(err: any): boolean {
  return err?.code === 'P2002';
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function isNotFoundError(err: any): boolean {
  return err?.code === 'P2025';
}
