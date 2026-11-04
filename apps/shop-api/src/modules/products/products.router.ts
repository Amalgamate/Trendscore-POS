/**
 * Products module — catalog CRUD and barcode lookup.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { prisma } from '../../lib/prisma';
import { parseBody, parseQuery, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';
import { toBaseQuantity, UnitConversionError } from '../sales/measured-units';

const ListProductsQuerySchema = z.object({
  category: z.string().optional(),
  search: z.string().optional(),
  lowStock: z.enum(['true', 'false']).optional(),
  active: z.enum(['true', 'false', 'all']).optional().default('true'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(200).default(100),
});

const StockListQuerySchema = z.object({
  category: z.string().optional(),
  search: z.string().optional(),
  stock: z.enum(['all', 'low', 'out']).default('all'),
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(500).default(200),
});

class ProductHasHistoryError extends Error {
  constructor(
    readonly counts: { saleItems: number; purchaseItems: number; refundItems: number },
  ) {
    super('Product has transaction history and cannot be permanently deleted. Archive it instead.');
  }
}

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
  purchaseContainerName: z.string().max(100).nullable().optional(),
  purchaseContainerSize: z.number().positive().nullable().optional(),
  quickQuantityPresets: z.array(z.string().trim().min(1).max(32)).max(20).optional().default([]),
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
  delta: z.number().finite().refine((value) => value !== 0),
  unit: z.string().min(1).max(16).optional(),
  reason: z.enum(['SPILLAGE', 'WASTAGE', 'DAMAGE', 'EXPIRY', 'CORRECTION']),
  note: z.string().max(500).optional(),
});

export function productsRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /products/stock/list — complete paged inventory snapshot with valuation.
  // Cost and retail values are included for all authenticated shop roles per D6.
  router.get('/stock/list', requireAuth, async (req, res) => {
    const query = parseQuery(StockListQuerySchema, req, res);
    if (!query) return;
    const page = query.page ?? 1;
    const limit = query.limit ?? 200;
    const where: Prisma.ProductWhereInput = {
      businessId,
      active: true,
      ...(query.category ? { category: { name: { equals: query.category, mode: 'insensitive' } } } : {}),
      ...(query.search ? { OR: [
        { name: { contains: query.search, mode: 'insensitive' } },
        { sku: { contains: query.search, mode: 'insensitive' } },
        { barcode: { contains: query.search, mode: 'insensitive' } },
      ] } : {}),
      ...(query.stock === 'low' ? { stock: { lte: prisma.product.fields.lowStockThreshold, gt: 0 } } : {}),
      ...(query.stock === 'out' ? { stock: { lte: 0 } } : {}),
    };
    try {
      const [products, total] = await Promise.all([
        prisma.product.findMany({
          where,
          select: {
            id: true, name: true, sku: true, barcode: true, category: { select: { name: true } },
            stock: true, unit: true, salePrice: true, costPrice: true, lowStockThreshold: true, varianceFlag: true,
          },
          orderBy: [{ category: { sortOrder: 'asc' } }, { name: 'asc' }],
          skip: (page - 1) * limit,
          take: limit,
        }),
        prisma.product.count({ where }),
      ]);
      const data = products.map((product) => {
        const quantity = new Prisma.Decimal(product.stock.toString());
        const costPrice = new Prisma.Decimal(product.costPrice.toString());
        const salePrice = new Prisma.Decimal(product.salePrice.toString());
        return {
          id: product.id, name: product.name, sku: product.sku, barcode: product.barcode,
          category: product.category?.name ?? null,
          quantity: quantity.toNumber(), unit: product.unit,
          salePrice: salePrice.toNumber(), costPrice: costPrice.toNumber(),
          valueAtCost: quantity.mul(costPrice).toDecimalPlaces(2).toNumber(),
          valueAtSellingPrice: quantity.mul(salePrice).toDecimalPlaces(2).toNumber(),
          lowStockThreshold: Number(product.lowStockThreshold.toString()),
          isNegative: quantity.isNegative(), varianceFlag: product.varianceFlag,
        };
      });
      const totals = data.reduce((sum, product) => ({
        quantity: sum.quantity.plus(product.quantity),
        valueAtCost: sum.valueAtCost.plus(product.valueAtCost),
        valueAtSellingPrice: sum.valueAtSellingPrice.plus(product.valueAtSellingPrice),
      }), { quantity: new Prisma.Decimal(0), valueAtCost: new Prisma.Decimal(0), valueAtSellingPrice: new Prisma.Decimal(0) });
      return send200(res, {
        data,
        totals: { quantity: totals.quantity.toNumber(), valueAtCost: totals.valueAtCost.toNumber(), valueAtSellingPrice: totals.valueAtSellingPrice.toNumber() },
        valuationBasis: { valueAtCost: 'quantity × costPrice; includes tax treatment as stored on product', valueAtSellingPrice: 'quantity × salePrice; indicative retail value, not realized revenue' },
        meta: { total, page, limit, pages: Math.ceil(total / limit) },
      });
    } catch (err) {
      console.error('products/stock/list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch stock list.');
    }
  });

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
    const { imageBase64, initialStock: _initialStock, ...productData } = body;

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

  // DELETE /products/:id — permanently purge a product with no transaction history.
  // Requires discardStock:true if the product has stock on hand.
  const DeleteProductSchema = z.object({ discardStock: z.boolean().optional() });

  router.delete('/:id', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    // Parse optional body — a plain DELETE with no body is valid (discardStock defaults to false).
    const bodyResult = DeleteProductSchema.safeParse(
      req.body && Object.keys(req.body).length > 0 ? req.body : {},
    );
    if (!bodyResult.success) {
      return sendError(res, 422, 'VALIDATION_ERROR', 'Request body is invalid.');
    }
    const body = bodyResult.data;
    const queryDiscardStock = z.enum(['true', 'false']).optional().safeParse(req.query.discardStock);
    if (!queryDiscardStock.success) {
      return sendError(res, 422, 'VALIDATION_ERROR', 'Query parameter discardStock must be true or false.');
    }
    const discardStock = queryDiscardStock.data === undefined
      ? body.discardStock === true
      : queryDiscardStock.data === 'true';
    const id = req.params.id;
    const auth = res.locals.auth as { userId: string; role: string };

    try {
      // (b) Scope by businessId; 404 if not found.
      const existing = await prisma.product.findFirst({
        where: { id, businessId },
        select: { id: true, name: true, sku: true, barcode: true, salePrice: true, costPrice: true, stock: true, active: true },
      });
      if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');

      // (c) History check — run three counts in parallel.
      const [saleItems, purchaseItems, refundItems] = await Promise.all([
        prisma.saleItem.count({ where: { productId: id } }),
        prisma.purchaseItem.count({ where: { productId: id } }),
        prisma.refundItem.count({ where: { productId: id } }),
      ]);
      if (saleItems > 0 || purchaseItems > 0 || refundItems > 0) {
        return sendError(
          res, 409, 'PRODUCT_HAS_HISTORY',
          'Product has transaction history and cannot be permanently deleted. Archive it instead.',
          { counts: { saleItems, purchaseItems, refundItems } },
        );
      }

      // (d) Stock guard — use Decimal-safe comparison.
      const stock = new Prisma.Decimal(existing.stock.toString());
      const hasStock = !stock.isZero();
      if (hasStock && !discardStock) {
        return sendError(
          res, 422, 'NON_ZERO_STOCK',
          'Product has stock on hand. Set discardStock:true to discard it and proceed.',
          { stock: Number(stock.toString()) },
        );
      }

      // (e) Purge transaction.
      await prisma.$transaction(async (tx) => {
        // Lock the row first.
        await tx.$queryRaw(Prisma.sql`SELECT id FROM products WHERE id = ${id}::uuid FOR UPDATE`);
        // Recheck after acquiring the same product lock used by sale and
        // receiving transactions so history cannot appear between the guard
        // and the purge.
        const [lockedSaleItems, lockedPurchaseItems, lockedRefundItems] = await Promise.all([
          tx.saleItem.count({ where: { productId: id } }),
          tx.purchaseItem.count({ where: { productId: id } }),
          tx.refundItem.count({ where: { productId: id } }),
        ]);
        if (lockedSaleItems > 0 || lockedPurchaseItems > 0 || lockedRefundItems > 0) {
          throw new ProductHasHistoryError({
            saleItems: lockedSaleItems,
            purchaseItems: lockedPurchaseItems,
            refundItems: lockedRefundItems,
          });
        }
        // SET LOCAL scopes the purge permission to this transaction only.
        await tx.$queryRaw(Prisma.sql`SELECT set_config('app.purge_product_id', ${id}, true)`);
        // Delete stock movements (trigger now allows this for this transaction).
        await tx.stockMovement.deleteMany({ where: { productId: id } });
        // Hard-delete the product (cascades product_images via onDelete: Cascade).
        await tx.product.delete({ where: { id } });
        // Audit log.
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'PRODUCT_PURGE',
            entityType: 'PRODUCT',
            entityId: id,
            beforeJson: {
              name: existing.name,
              sku: existing.sku,
              barcode: existing.barcode,
              salePrice: existing.salePrice.toString(),
              costPrice: existing.costPrice.toString(),
              stock: existing.stock.toString(),
              discardedQty: hasStock ? existing.stock.toString() : '0',
            },
          },
        });
      });

      return send200(res, { id, deleted: true });
    } catch (err) {
      if (err instanceof ProductHasHistoryError) {
        return sendError(
          res, 409, 'PRODUCT_HAS_HISTORY', err.message,
          { counts: err.counts },
        );
      }
      console.error('products/purge error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to delete product.');
    }
  });

  // POST /products/:id/archive — set active=false (preserves all history).
  router.post('/:id/archive', requireAuth, requireRole('OWNER', 'MANAGER'), async (req, res) => {
    const auth = res.locals.auth as { userId: string; role: string };
    try {
      const existing = await prisma.product.findFirst({
        where: { id: req.params.id, businessId },
        select: { id: true, name: true, sku: true, active: true },
      });
      if (!existing) return sendError(res, 404, 'NOT_FOUND', 'Product not found.');
      // Idempotent: already inactive is fine.
      if (!existing.active) return send200(res, { id: existing.id, active: false });
      await prisma.$transaction(async (tx) => {
        await tx.product.update({ where: { id: existing.id }, data: { active: false } });
        await tx.auditLog.create({
          data: {
            businessId,
            userId: auth.userId,
            action: 'PRODUCT_ARCHIVED',
            entityType: 'PRODUCT',
            entityId: existing.id,
            beforeJson: { name: existing.name, sku: existing.sku, active: true },
          },
        });
      });
      return send200(res, { id: existing.id, active: false });
    } catch (err) {
      console.error('products/archive error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to archive product.');
    }
  });

  // POST /products/:id/adjust-stock
  router.post('/:id/adjust-stock', requireAuth, requireRole('SUPER_ADMIN', 'OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(StockAdjustSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    const productId = req.params.id;
    if (!productId) return sendError(res, 400, 'BAD_REQUEST', 'Missing product ID.');

    try {
      const result = await prisma.$transaction(async (tx) => {
        await tx.$queryRaw(
          Prisma.sql`SELECT "id" FROM "products"
            WHERE "businessId" = ${businessId}::uuid
              AND "id" = ${productId}::uuid
            FOR UPDATE`,
        );
        const product = await tx.product.findFirstOrThrow({ where: { id: productId, businessId } });
        const unit = body.unit ?? product.unit;
        const milliDelta = toBaseQuantity(Math.abs(body.delta), unit, product.unit);
        const delta = new Prisma.Decimal(milliDelta).dividedBy(1000).mul(Math.sign(body.delta));
        const before = new Prisma.Decimal(product.stock.toString());
        const newStock = before.plus(delta);

        if (newStock.isNegative()) {
          throw new Error('STOCK_NEGATIVE');
        }

        await tx.product.update({
          where: { id: productId },
          data: { stock: newStock },
        });

        const movement = await tx.stockMovement.create({
          data: {
            businessId,
            productId,
            createdById: auth.userId,
            type: delta.isPositive() ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
            quantity: delta,
            balanceAfter: newStock,
            reason: body.reason,
            note: body.note,
          },
        });

        await tx.auditLog.create({ data: {
          businessId, userId: auth.userId, action: 'STOCK_ADJUSTED',
          entityType: 'PRODUCT', entityId: productId,
          beforeJson: { stock: before.toString() },
          afterJson: { stock: newStock.toString(), delta: delta.toString(), unit, reason: body.reason, movementId: movement.id },
        } });

        return { productId, newStock: newStock.toNumber(), delta: delta.toNumber(), unit: product.unit, movementId: movement.id };
      });

      return send200(res, result);
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'STOCK_NEGATIVE') {
        return sendError(res, 422, 'STOCK_NEGATIVE', 'Adjustment would drive stock below zero.');
      }
      if (err instanceof UnitConversionError) {
        return sendError(res, 422, 'INVALID_STOCK_UNIT', err.message);
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
    purchaseContainerName: p.purchaseContainerName,
    purchaseContainerSize: p.purchaseContainerSize === null ? null : Number(p.purchaseContainerSize),
    quickQuantityPresets: p.quickQuantityPresets,
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
