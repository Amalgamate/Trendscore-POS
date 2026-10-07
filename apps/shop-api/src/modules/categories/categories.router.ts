/**
 * Categories module — product category management.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { parseBody, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const CreateCategorySchema = z.object({
  name: z.string().min(1).max(100),
  colorHex: z.string().regex(/^#[0-9a-fA-F]{6}$/).default('#0D9488'),
  sortOrder: z.number().int().default(0),
});

export function categoriesRouter(businessId: string): Router {
  const router = ExpressRouter();

  // GET /categories
  router.get('/', requireAuth, async (req, res) => {
    try {
      const categories = await prisma.category.findMany({
        where: { businessId },
        include: { _count: { select: { products: true } } },
        orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
      });
      return send200(res, categories.map(c => ({
        id: c.id, name: c.name, colorHex: c.colorHex,
        sortOrder: c.sortOrder, productCount: c._count.products,
      })));
    } catch (err) {
      console.error('categories/list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch categories.');
    }
  });

  // POST /categories
  router.post('/', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(CreateCategorySchema, req, res);
    if (!body) return;
    try {
      const cat = await prisma.category.create({ data: { businessId, ...body } });
      return send201(res, cat);
    } catch (err: unknown) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if ((err as any)?.code === 'P2002')
        return sendError(res, 409, 'DUPLICATE_NAME', 'A category with that name already exists.');
      console.error('categories/create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create category.');
    }
  });

  // PATCH /categories/:id
  router.patch('/:id', requireAuth, requireRole('OWNER', 'MANAGER', 'STOCK_CLERK'), async (req, res) => {
    const body = parseBody(CreateCategorySchema.partial(), req, res);
    if (!body) return;
    try {
      const cat = await prisma.category.update({ where: { id: req.params.id }, data: body });
      return send200(res, cat);
    } catch (err: unknown) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      if ((err as any)?.code === 'P2025') return sendError(res, 404, 'NOT_FOUND', 'Category not found.');
      console.error('categories/update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update category.');
    }
  });

  return router;
}
