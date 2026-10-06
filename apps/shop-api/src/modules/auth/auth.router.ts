/**
 * Auth module — PIN-based cashier login.
 *
 * Produces a short-lived JWT that the POS includes in subsequent requests.
 * Rate limiting must be applied at the reverse-proxy layer (Traefik); this
 * handler trusts that the caller has already been rate-limited.
 */
import type { Router } from 'express';
import { Router as ExpressRouter } from 'express';
import { z } from 'zod';
import jwt from 'jsonwebtoken';
import argon2 from 'argon2';
import { prisma } from '../../lib/prisma';
import { parseBody, send200, sendError } from '../../lib/http';

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';
const JWT_EXPIRY = process.env.JWT_EXPIRY ?? '8h'; // one shift

const LoginSchema = z.object({
  phone: z.string().min(9, 'Phone number required'),
  pin: z.string().min(4).max(8),
});

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
        where: { phone: body.phone },
        select: { id: true, fullName: true, role: true, pinHash: true, active: true },
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
        user: { id: user.id, fullName: user.fullName, role: user.role },
      });
    } catch (err) {
      console.error('auth/login error:', err);
      return sendError(res, 500, 'SERVER_ERROR', 'An unexpected error occurred.');
    }
  });

  return router;
}
