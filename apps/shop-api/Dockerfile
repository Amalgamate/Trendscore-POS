# Shop instance API image.
#
# One image serves every shop; per-shop configuration arrives through
# environment variables injected by the provisioning engine. Instances pin
# to an immutable tag so rollback is always possible.

FROM node:20-alpine AS builder
WORKDIR /app

# Install dependencies first for layer caching.
COPY package.json package-lock.json* ./
COPY packages/payment-provider/package.json ./packages/payment-provider/
COPY packages/design-tokens/package.json ./packages/design-tokens/
RUN npm ci --omit=dev --ignore-scripts || npm install --omit=dev --ignore-scripts

# Generate the Prisma client against the schema.
COPY prisma ./prisma
RUN npx prisma generate

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ----------------------------------------------------------------------
FROM node:20-alpine AS runtime
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=4000

# Run unprivileged. Never root in a container.
RUN addgroup -S retail && adduser -S retail -G retail

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package.json ./package.json

USER retail
EXPOSE 4000

# The provisioning engine polls this before marking the instance READY.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:4000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/index.js"]
