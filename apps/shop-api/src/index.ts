import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { healthHandler } from './modules/health/health';
import { authRouter } from './modules/auth/auth.router';
import { productsRouter } from './modules/products/products.router';
import { customersRouter } from './modules/customers/customers.router';
import { salesRouter } from './modules/sales/sales.router';
import { categoriesRouter } from './modules/categories/categories.router';
import { businessRouter } from './modules/business/business.router';
import { deliveryRouter } from './modules/delivery/delivery.router';

const PORT = Number(process.env.PORT ?? 4000);
const VERSION = process.env.APP_VERSION ?? 'dev';
const STARTED_AT = Date.now();

/**
 * The BUSINESS_ID env var scopes every route to a single shop database.
 * In production, each shop runs its own container with its own Postgres.
 * See ADR-0001 for the isolation rationale.
 */
const BUSINESS_ID = process.env.BUSINESS_ID ?? '';

const log = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  redact: ['req.headers.authorization', 'req.headers.cookie', '*.passwordHash', '*.pinHash'],
});

const app = express();

app.use(helmet({
  // Required for Flutter Web WASM isolation headers
  crossOriginOpenerPolicy: { policy: 'same-origin' },
  crossOriginEmbedderPolicy: { policy: 'require-corp' },
}));
app.use(cors({
  origin: process.env.CORS_ORIGIN ?? ['http://localhost:8080', 'http://localhost:3000'],
  credentials: true,
}));
app.use(express.json({ limit: '1mb' }));
app.use(pinoHttp({ logger: log }));

// ─── Unauthenticated ─────────────────────────────────────────────────────────
app.get('/health', healthHandler({}, { version: VERSION, startedAt: STARTED_AT }));
app.use('/auth', authRouter());

// ─── Business-scoped authenticated routes ────────────────────────────────────
if (BUSINESS_ID) {
  app.use('/products', productsRouter(BUSINESS_ID));
  app.use('/categories', categoriesRouter(BUSINESS_ID));
  app.use('/customers', customersRouter(BUSINESS_ID));
  app.use('/sales', salesRouter(BUSINESS_ID));
  app.use('/business', businessRouter(BUSINESS_ID));
  app.use('/delivery', deliveryRouter(BUSINESS_ID));
} else {
  log.warn('BUSINESS_ID is not set — business routes are disabled. Set the env var to enable them.');
}

// ─── 404 catch-all ───────────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Route not found.' } });
});

const server = app.listen(PORT, () => {
  log.info({ port: PORT, version: VERSION, businessId: BUSINESS_ID || 'unset' }, 'shop-api listening');
});

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    log.info({ signal }, 'shutting down');
    server.close(() => process.exit(0));
  });
}
