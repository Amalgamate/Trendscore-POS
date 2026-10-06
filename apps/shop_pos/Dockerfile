# Build the Flutter POS as a static web application, then serve it with Node.
# Match the Flutter SDK used to generate pubspec.lock. A moving stable tag
# can make `--enforce-lockfile` fail when SDK-bundled package versions change.
FROM ghcr.io/cirruslabs/flutter:3.38.3 AS builder
WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get --enforce-lockfile

COPY . .
RUN flutter build web --release

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080

RUN addgroup -S retail && adduser -S retail -G retail
COPY --chown=retail:retail serve.mjs ./serve.mjs
COPY --from=builder --chown=retail:retail /app/build/web ./build/web

USER retail
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "serve.mjs"]
