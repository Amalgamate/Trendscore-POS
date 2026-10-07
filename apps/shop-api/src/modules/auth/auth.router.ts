/**
 * Auth module — PIN-based cashier login.
 *
 * Produces a short-lived JWT that the POS includes in subsequent requests.
 * Rate limiting must be applied at the reverse-proxy layer; this
 * handler trusts that the caller has already been rate-limited.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import jwt from 'jsonwebtoken';
import argon2 from 'argon2';
import { prisma } from '../../lib/prisma';
import { parseBody, send200, send201, sendError } from '../../lib/http';
import { requireAuth, requireRole } from '../../lib/auth.middleware';

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';
const JWT_EXPIRY = process.env.JWT_EXPIRY ?? '8h'; // one shift

const LoginSchema = z.object({
  phone: z.string().min(9, 'Phone number required'),
  pin: z.string().regex(/^\d{4,6}$/, 'PIN must be 4 to 6 digits'),
});

const StaffCreateSchema = z.object({
  fullName: z.string().trim().min(1).max(120),
  phone: z.string().min(9).max(24),
  pin: z.string().regex(/^\d{4,6}$/, 'PIN must be 4 to 6 digits'),
  role: z.enum(['OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK']),
});

const StaffUpdateSchema = z.object({
  fullName: z.string().trim().min(1).max(120).optional(),
  phone: z.string().min(9).max(24).optional(),
  pin: z.string().regex(/^\d{4,6}$/, 'PIN must be 4 to 6 digits').optional(),
  role: z.enum(['OWNER', 'MANAGER', 'CASHIER', 'STOCK_CLERK']).optional(),
  active: z.boolean().optional(),
}).refine((data) => Object.keys(data).length > 0, 'At least one field is required.');

const ChangePinSchema = z.object({
  pin: z.string().regex(/^\d{4,6}$/, 'PIN must be 4 to 6 digits'),
});

function normalizePhone(input: string): string {
  const digits = input.replace(/\D/g, '');
  if (digits.startsWith('254')) return digits;
  if (digits.startsWith('0')) return `254${digits.slice(1)}`;
  if (digits.startsWith('7') && digits.length === 9) return `254${digits}`;
  throw new Error('Enter a valid Kenyan phone number.');
}

function safeUser(user: { id: string; fullName: string; phone: string; role: string; active: boolean }) {
  return { id: user.id, fullName: user.fullName, phone: user.phone, role: user.role, active: user.active };
}

export function authRouter(): Router {
  const router = ExpressRouter();

  /**
   * POST /auth/login
   * Body: { phone, pin }
   * Returns: { token, user: { id, fullName, role } }
   */
  router.post('/login', async (req, res) => {
    const body = parseBody(LoginSchema, req, res);
    if (!body) return;

    try {
      const user = await prisma.user.findUnique({
        where: { phone: normalizePhone(body.phone) },
        select: { id: true, fullName: true, phone: true, role: true, pinHash: true, active: true, mustChangePin: true },
      });

      if (!user || !user.active) {
        // Deliberate: same response for "user not found" and "wrong PIN"
        return sendError(res, 401, 'INVALID_CREDENTIALS', 'Phone number or PIN is incorrect.');
      }

      const pinValid = await argon2.verify(user.pinHash, body.pin);
      if (!pinValid) {
        return sendError(res, 401, 'INVALID_CREDENTIALS', 'Phone number or PIN is incorrect.');
      }

      // Update last login time
      await prisma.user.update({
        where: { id: user.id },
        data: { lastLoginAt: new Date() },
      });

      const token = jwt.sign(
        { sub: user.id, role: user.role, name: user.fullName },
        JWT_SECRET,
        { expiresIn: JWT_EXPIRY } as jwt.SignOptions,
      );

      return send200(res, {
        token,
        user: {
          id: user.id,
          fullName: user.fullName,
          phone: user.phone,
          role: user.role,
          mustChangePin: user.mustChangePin,
        },
      });
    } catch (err) {
      if (err instanceof Error && err.message === 'Enter a valid Kenyan phone number.') {
        return sendError(res, 400, 'INVALID_PHONE', err.message);
      }
      console.error('auth/login error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'An unexpected error occurred.');
    }
  });

  router.post('/change-pin', requireAuth, async (req, res) => {
    const body = parseBody(ChangePinSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    try {
      const pinHash = await argon2.hash(body.pin, { type: argon2.argon2id });
      await prisma.user.update({
        where: { id: auth.userId },
        data: { pinHash, mustChangePin: false },
      });
      return send200(res, { ok: true });
    } catch (err) {
      console.error('auth/change-pin error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Could not update the PIN.');
    }
  });

  // Staff management is owner-only; PIN hashes are never returned.
  router.get('/users', requireAuth, requireRole('OWNER'), async (_req, res) => {
    try {
      const users = await prisma.user.findMany({
        select: { id: true, fullName: true, phone: true, role: true, active: true },
        orderBy: [{ active: 'desc' }, { fullName: 'asc' }],
      });
      return send200(res, { data: users.map(safeUser) });
    } catch (err) {
      console.error('auth/users list error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to fetch staff accounts.');
    }
  });

  router.post('/users', requireAuth, requireRole('OWNER'), async (req, res) => {
    const body = parseBody(StaffCreateSchema, req, res);
    if (!body) return;
    try {
      const phone = normalizePhone(body.phone);
      const pinHash = await argon2.hash(body.pin, { type: argon2.argon2id });
      const user = await prisma.user.create({
        data: { fullName: body.fullName, phone, pinHash, role: body.role },
        select: { id: true, fullName: true, phone: true, role: true, active: true },
      });
      return send201(res, { data: safeUser(user) });
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'Enter a valid Kenyan phone number.') {
        return sendError(res, 400, 'INVALID_PHONE', err.message);
      }
      if (isUniqueConstraintError(err)) {
        return sendError(res, 409, 'DUPLICATE_PHONE', 'A staff account already uses that phone number.');
      }
      console.error('auth/users create error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to create staff account.');
    }
  });

  router.patch('/users/:id', requireAuth, requireRole('OWNER'), async (req, res) => {
    const body = parseBody(StaffUpdateSchema, req, res);
    if (!body) return;
    const auth = res.locals.auth;
    try {
      const current = await prisma.user.findUnique({ where: { id: req.params.id } });
      if (!current) return sendError(res, 404, 'NOT_FOUND', 'Staff account not found.');

      const nextRole = body.role ?? current.role;
      const nextActive = body.active ?? current.active;
      if (current.id === auth.userId && (nextRole !== 'OWNER' || !nextActive)) {
        return sendError(res, 409, 'LAST_OWNER', 'You cannot deactivate or demote your own owner account.');
      }
      if (current.role === 'OWNER' && current.active && (nextRole !== 'OWNER' || !nextActive)) {
        const activeOwners = await prisma.user.count({ where: { role: 'OWNER', active: true } });
        if (activeOwners <= 1) {
          return sendError(res, 409, 'LAST_OWNER', 'Create another active owner before demoting this account.');
        }
      }

      const phone = body.phone === undefined ? undefined : normalizePhone(body.phone);
      const pinHash = body.pin === undefined
        ? undefined
        : await argon2.hash(body.pin, { type: argon2.argon2id });
      const user = await prisma.user.update({
        where: { id: req.params.id },
        data: {
          fullName: body.fullName,
          phone,
          pinHash,
          role: body.role,
          active: body.active,
        },
        select: { id: true, fullName: true, phone: true, role: true, active: true },
      });
      return send200(res, { data: safeUser(user) });
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'Enter a valid Kenyan phone number.') {
        return sendError(res, 400, 'INVALID_PHONE', err.message);
      }
      if (isUniqueConstraintError(err)) {
        return sendError(res, 409, 'DUPLICATE_PHONE', 'A staff account already uses that phone number.');
      }
      console.error('auth/users update error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'Failed to update staff account.');
    }
  });

  return router;
}

function isUniqueConstraintError(err: unknown): boolean {
  return typeof err === 'object' && err !== null && 'code' in err && err.code === 'P2002';
}
