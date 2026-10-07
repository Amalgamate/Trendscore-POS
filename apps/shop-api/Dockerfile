# Shop instance API image.
#
# One image serves every shop; per-shop configuration arrives through
# environment variables injected by the provisioning engine. Instances pin
# to an immutable tag so rollback is always possible.
#
# Build context is apps/shop-api, so this file must not reference anything
# outside that directory. It depends on no workspace packages.

FROM node:20-alpine AS builder
WORKDIR /app

# Dependencies first, for layer caching. There is no lockfile in this
# workspace yet, so `npm ci` is not usable here; `npm install` is used and
# the resulting image is still pinned by tag, never by digest drift.
COPY package.json ./
RUN npm install --omit=dev --ignore-scripts --no-audit --no-fund

# Prisma client generation needs the CLI, which is a devDependency.
COPY prisma ./prisma
RUN npm install --no-save --ignore-scripts --no-audit --no-fund prisma@6 @prisma/client@6 \
 && npx prisma generate

COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

# Fail the build, not the deployment, if an entrypoint is missing.
RUN test -f dist/index.js && test -f dist/scripts/seed.js && test -f dist/scripts/create-owner.js && test -f dist/scripts/create-super-admin.js

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
