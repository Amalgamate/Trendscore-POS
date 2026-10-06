/**
 * Shared HTTP helpers: uniform error shapes and request validation.
 */
import type { Request, Response } from 'express';
import { ZodError, type ZodSchema } from 'zod';

export interface ApiError {
  code: string;
  message: string;
  details?: unknown;
}

export function sendError(res: Response, status: number, code: string, message: string, details?: unknown) {
  const body: ApiError = { code, message, ...(details !== undefined ? { details } : {}) };
  return res.status(status).json({ error: body });
}

export function send200<T>(res: Response, data: T) {
  return res.status(200).json(data);
}

export function send201<T>(res: Response, data: T) {
  return res.status(201).json(data);
}

export function parseBody<T>(schema: ZodSchema<T>, req: Request, res: Response): T | null {
  const result = schema.safeParse(req.body);
  if (!result.success) {
    sendError(res, 422, 'VALIDATION_ERROR', 'Request body is invalid', formatZodError(result.error));
    return null;
  }
  return result.data;
}

export function parseQuery<T>(schema: ZodSchema<T>, req: Request, res: Response): T | null {
  const result = schema.safeParse(req.query);
  if (!result.success) {
    sendError(res, 422, 'VALIDATION_ERROR', 'Query parameters are invalid', formatZodError(result.error));
    return null;
  }
  return result.data;
}

function formatZodError(error: ZodError) {
  return error.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
}
