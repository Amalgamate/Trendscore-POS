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
import { requireAuth, requireRole } from '../../lib/auth.middleware';

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
  description: z.string().max(5000).nullable().optional(),
  notes: z.string().max(5000).nullable().optional(),
  sku: z.string().max(100).optional(),
  barcode: z.string().max(100).optional(),
  groupId: z.string().max(100).optional(),
  variantLabel: z.string().max(100).optional(),
  imageBase64: z.string().max(1_000_000).nullable().optional(),
  isPublished: z.boolean().default(false),
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
  .extend({
    active: z.boolean().optional(),
    imageBase64: z.string().max(1_000_000).nullable().optional(),
  });

const productRelations = {
  category: { select: { id: true, name: true, colorHex: true } },
  images: { orderBy: { position: 'asc' as const }, take: 1 },
};

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

  // GET /products/storefront/:id/image — serve one published product image.
  router.get('/storefront/:id/image', async (req, res) => {
    try {
      const product = await prisma.product.findFirst({
        where: {
          id: req.params.id,
          businessId,
          active: true,
          isPublished: true,
        },
        include: { images: { where: { position: 0 }, take: 1 } },
      });
      const imageData = product?.images[0]?.imageData;
      const match = imageData?.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/]+=*)$/);
      const imageType = match?.[1];
      const encodedImage = match?.[2];
      if (!imageType || !encodedImage) {
        return sendError(res, 404, 'NOT_FOUND', 'Published product image not found.');
      }
      res.setHeader('Cache-Control', 'public, max-age=300, s-maxage=300');
      return res.type(`image/${imageType}`).send(Buffer.from(encodedImage, 'base64'));
    } catch (err) {
      console.error('products/storefront image error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch product image.');
    }
  });

  // GET /products/storefront — publish only safe catalog fields publicly.
  router.get('/storefront', async (_req, res) => {
    try {
      const products = await prisma.product.findMany({
        where: { businessId, active: true, isPublished: true },
        include: productRelations,
        orderBy: [{ category: { sortOrder: 'asc' } }, { name: 'asc' }],
      });
      return send200(res, {
        data: products.map((product) => ({
          id: product.id,
          name: product.name,
          variantLabel: product.variantLabel,
          category: product.category?.name ?? 'Other',
          description: product.description,
          salePrice: Number(product.salePrice),
          unit: product.unit,
          available: Number(product.stock) > 0,
          imageUrl: product.images[0]
            ? `products/storefront/${product.id}/image`
            : null,
        })),
      });
    } catch (err) {
      console.error('products/storefront error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch published products.');
    }
  });

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
          include: productRelations,
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
        include: productRelations,
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
        include: productRelations,
      });
      if (!product) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      return send200(res, mapProduct(product));
    } catch (err) {
      console.error('products/get error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch product.');
    }
  });

  // POST /products
  router.post('/', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(CreateProductSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    if (body.isPublished && !['OWNER', 'MANAGER', 'SUPER_ADMIN'].includes(auth.role)) {
      return sendError(res, 403, 'FORBIDDEN', 'Only an owner or manager can publish products to the web shop.');
    }

    const initialStock = body.initialStock ?? 0;
    const costPrice = body.costPrice ?? 0;
    const vatRate = body.vatRate ?? 0.16;
    const unit = body.unit ?? 'pc';
    const lowStockThreshold = body.lowStockThreshold ?? 5;
    const { imageBase64, ...productData } = body;

    try {
      const product = await prisma.$transaction(async (tx) => {
        const p = await tx.product.create({
          data: {
            businessId,
            ...productData,
            costPrice,
            vatRate,
            unit,
            stock: initialStock,
            lowStockThreshold,
            publishedAt: body.isPublished ? new Date() : null,
          },
          include: productRelations,
        });
        if (imageBase64) {
          await tx.productImage.create({
            data: {
              productId: p.id,
              imageData: imageBase64,
              altText: p.name,
            },
          });
        }

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
        return imageBase64
          ? tx.product.findUniqueOrThrow({
              where: { id: p.id },
              include: productRelations,
            })
          : p;
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
  router.post('/import', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
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
  router.patch('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(UpdateProductSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;

    try {
      // Ownership check — ensure this product belongs to the routed business.
      const existing = await prisma.product.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true, isPublished: true, publishedAt: true },
      });
      if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      if (
        body.isPublished !== undefined &&
        body.isPublished !== existing.isPublished &&
        !['OWNER', 'MANAGER', 'SUPER_ADMIN'].includes(auth.role)
      ) {
        return sendError(res, 403, 'FORBIDDEN', 'Only an owner or manager can change web-shop publication.');
      }

      const { imageBase64, ...productData } = body;
      const product = await prisma.$transaction(async (tx) => {
        const updated = await tx.product.update({
          where: { id: existing.id },
          data: {
            ...productData,
            ...(body.isPublished === undefined
              ? {}
              : {
                  publishedAt: body.isPublished
                    ? existing.publishedAt ?? new Date()
                    : null,
                }),
          },
          include: productRelations,
        });
        if (imageBase64 !== undefined) {
          if (imageBase64 === null) {
            await tx.productImage.deleteMany({ where: { productId: existing.id } });
          } else {
            await tx.productImage.upsert({
              where: { productId_position: { productId: existing.id, position: 0 } },
              create: {
                productId: existing.id,
                imageData: imageBase64,
                altText: updated.name,
              },
              update: {
                imageData: imageBase64,
                altText: updated.name,
              },
            });
          }
        }
        return tx.product.findUniqueOrThrow({
          where: { id: existing.id },
          include: productRelations,
        });
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
  router.delete('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
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
  router.post('/:id/adjust-stock', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
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
    description: p.description,
    notes: p.notes,
    sku: p.sku,
    barcode: p.barcode,
    groupId: p.groupId,
    variantLabel: p.variantLabel,
    imageBase64: p.images?.[0]?.imageData ?? null,
    category: p.category,
    salePrice: Number(p.salePrice),
    costPrice: Number(p.costPrice),
    vatRate: Number(p.vatRate),
    unit: p.unit,
    stock: Number(p.stock),
    lowStockThreshold: Number(p.lowStockThreshold),
    active: p.active,
    isPublished: p.isPublished,
    publishedAt: p.publishedAt,
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
