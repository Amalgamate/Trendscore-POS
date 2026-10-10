/**
 * JWT authentication middleware.
 * Attaches decoded token payload to res.locals.auth.
 */
import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { sendError } from './http';
import { prisma } from './prisma';

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';

export interface AuthLocals {
  userId: string;
  role: string;
  name: string;
}

export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return sendError(res, 401, 'NO_TOKEN', 'Authorization header missing or malformed.');
  }

  const token = header.slice(7);
  let payload: jwt.JwtPayload;
  try {
    payload = jwt.verify(token, JWT_SECRET) as jwt.JwtPayload;
  } catch {
    return sendError(res, 401, 'INVALID_TOKEN', 'Token is invalid or has expired. Please log in again.');
  }
  const userId = payload['sub'];
  if (typeof userId !== 'string') {
    return sendError(res, 401, 'INVALID_TOKEN', 'Token is invalid or has expired. Please log in again.');
  }

  try {
    // Refresh role and active status from the database on every request, so a
    // demotion or deactivation takes effect immediately despite an old JWT.
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, fullName: true, role: true, active: true, mustChangePin: true },
    });
    if (!user || !user.active) {
      return sendError(res, 401, 'INVALID_TOKEN', 'This staff account is inactive or no longer exists.');
    }
    const isPinChangeRequest = req.method === 'POST' && req.baseUrl === '/auth' && req.path === '/change-pin';
    if (user.mustChangePin && !isPinChangeRequest) {
      return sendError(res, 403, 'PIN_CHANGE_REQUIRED', 'Change your initial PIN before using the POS.');
    }
    res.locals.auth = { userId: user.id, role: user.role, name: user.fullName } satisfies AuthLocals;
    return next();
  } catch (error) {
    return next(error);
  }
}

/** Restrict an authenticated route to the listed server-side roles. */
export function requireRole(...roles: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    const auth = res.locals.auth as AuthLocals | undefined;
    if (!auth) return sendError(res, 401, 'NO_TOKEN', 'Authentication is required.');
    const isSystemAdminWithOwnerAccess =
      auth.role === 'SUPER_ADMIN' && roles.includes('OWNER');
    if (!roles.includes(auth.role) && !isSystemAdminWithOwnerAccess) {
      return sendError(res, 403, 'FORBIDDEN', 'Your account does not have permission to do this.');
    }
    return next();
  };
}
