/**
 * JWT authentication middleware.
 * Attaches decoded token payload to res.locals.auth.
 */
import type { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { sendError } from './http';

const JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-in-production';

export interface AuthLocals {
  userId: string;
  role: string;
  name: string;
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return sendError(res, 401, 'NO_TOKEN', 'Authorization header missing or malformed.');
  }

  const token = header.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET) as jwt.JwtPayload;
    res.locals.auth = {
      userId: payload['sub'] as string,
      role: payload['role'] as string,
      name: payload['name'] as string,
    } satisfies AuthLocals;
    return next();
  } catch {
    return sendError(res, 401, 'INVALID_TOKEN', 'Token is invalid or has expired. Please log in again.');
  }
}
