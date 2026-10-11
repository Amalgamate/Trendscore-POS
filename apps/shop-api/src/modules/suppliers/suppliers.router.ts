/**
 * Supplier directory — vendor records used by purchasing.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import { prisma } from '../../lib/prisma';
import { parseBody, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const CreateSupplierSchema = z.object({
  name: z.string().trim().min(1).max(200),
  phone: z.string().trim().max(40).optional(),
  email: z.string().trim().email().optional(),
  address: z.string().trim().max(500).optional(),
});

function mapSupplier(supplier: {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  balance: unknown;
  active: boolean;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: supplier.id,
    name: supplier.name,
    phone: supplier.phone,
    email: supplier.email,
    address: supplier.address,
    balance: Number(supplier.balance),
    active: supplier.active,
    createdAt: supplier.createdAt,
    updatedAt: supplier.updatedAt,
  };
}

export function suppliersRouter(businessId: string): Router {
  const router = ExpressRouter();

  router.get(
    '/',
    requireAuth,
    requireRole('OWNER', 'MANAGER', 'SUPER_ADMIN', 'STOCK_CLERK'),
    async (_req, res) => {
      try {
        const suppliers = await prisma.supplier.findMany({
          where: { businessId, active: true },
          orderBy: { name: 'asc' },
        });
        return send200(res, { data: suppliers.map(mapSupplier) });
      } catch (error) {
        console.error('suppliers/list error:', error);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch suppliers.');
      }
    },
  );

  router.post(
    '/',
    requireAuth,
    requireRole('OWNER', 'MANAGER', 'SUPER_ADMIN'),
    async (req, res) => {
      const body = parseBody(CreateSupplierSchema, req, res);
      if (!body) return;

      try {
        const supplier = await prisma.supplier.create({
          data: { businessId, ...body },
        });
        return send201(res, { data: mapSupplier(supplier) });
      } catch (error) {
        console.error('suppliers/create error:', error);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to create supplier.');
      }
    },
  );

  router.delete(
    '/:id',
    requireAuth,
    requireRole('OWNER', 'MANAGER', 'SUPER_ADMIN'),
    async (req, res) => {
      try {
        const supplier = await prisma.supplier.findFirst({
          where: { id: req.params.id, businessId },
        });
        if (!supplier) {
          return sendError(res, 404, 'NOT_FOUND', 'Supplier not found.');
        }
        if (!supplier.active) {
          return sendError(
            res,
            409,
            'ALREADY_ARCHIVED',
            'Supplier is already archived.',
          );
        }
        if (Number(supplier.balance) !== 0) {
          return sendError(
            res,
            409,
            'OUTSTANDING_BALANCE',
            'Settle the supplier balance before removing this supplier.',
          );
        }

        const result = await prisma.supplier.updateMany({
          where: {
            id: supplier.id,
            businessId,
            active: true,
            balance: 0,
          },
          data: { active: false },
        });
        if (result.count === 0) {
          return sendError(
            res,
            409,
            'SUPPLIER_CHANGED',
            'Supplier status or balance changed. Refresh and try again.',
          );
        }

        return send200(res, { data: { id: supplier.id, active: false } });
      } catch (error) {
        console.error('suppliers/archive error:', error);
        return sendError(res, 500, 'SERVER_ERROR', 'Failed to remove supplier.');
      }
    },
  );

  return router;
}
