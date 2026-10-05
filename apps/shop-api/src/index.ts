import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import pino from 'pino';
import pinoHttp from 'pino-http';
import { healthHandler } from './modules/health/health';

const PORT = Number(process.env.PORT ?? 4000);
const VERSION = process.env.APP_VERSION ?? 'dev';
const STARTED_AT = Date.now();

const log = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  redact: ['req.headers.authorization', 'req.headers.cookie', '*.passwordHash', '*.pinHash'],
});

const app = express();

app.use(helmet());
app.use(cors({ origin: process.env.CORS_ORIGIN ?? false }));
app.use(express.json({ limit: '1mb' }));
app.use(pinoHttp({ logger: log }));

// Unauthenticated: the provisioning engine and Traefik poll this directly.
// It exposes component status only, never business data.
app.get('/health', healthHandler({}, { version: VERSION, startedAt: STARTED_AT }));

const server = app.listen(PORT, () => {
  log.info({ port: PORT, version: VERSION }, 'shop-api listening');
});

for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.on(signal, () => {
    log.info({ signal }, 'shutting down');
    server.close(() => process.exit(0));
  });
}
