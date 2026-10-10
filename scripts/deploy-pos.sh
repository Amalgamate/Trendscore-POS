#!/usr/bin/env bash
set -euo pipefail

POS_IMAGE="${1:?POS image reference required}"
API_IMAGE="${2:?shop-api image reference required}"
WEB_IMAGE="${3:?storefront image reference required}"
DOMAIN="${4:?POS domain required}"
SHOP_DOMAIN="${5:?storefront domain required}"
EMAIL="${6:?certificate email required}"
DEPLOY_ID="${7:?deploy id required}"
ADMIN_CONFIG="${8:?temporary super-admin credential file required}"
DOCKER_CONFIG="${DOCKER_CONFIG:?temporary Docker config required}"
BASE_DIR=/opt/retailpos-live
NETWORK=retailpos-live-net
POSTGRES=retailpos-live-postgres

[[ "$POS_IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] || { echo "Invalid POS image reference" >&2; exit 2; }
[[ "$API_IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] || { echo "Invalid API image reference" >&2; exit 2; }
[[ "$WEB_IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] || { echo "Invalid storefront image reference" >&2; exit 2; }
[[ "$DOMAIN" =~ ^[a-z0-9.-]+$ ]] || { echo "Invalid domain" >&2; exit 2; }
[[ "$SHOP_DOMAIN" =~ ^[a-z0-9.-]+$ ]] || { echo "Invalid storefront domain" >&2; exit 2; }
[[ "$DOMAIN" != "$SHOP_DOMAIN" ]] || { echo "POS and storefront domains must be different" >&2; exit 2; }
[[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { echo "Invalid certificate email" >&2; exit 2; }
[[ "$DEPLOY_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Invalid deploy id" >&2; exit 2; }
[[ -r "$ADMIN_CONFIG" ]] || { echo "Temporary super-admin credential file is missing" >&2; exit 2; }

DOCKER=(docker --config "$DOCKER_CONFIG")
if ! docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker --config "$DOCKER_CONFIG")
fi
cleanup() {
  rm -f "$ADMIN_CONFIG"
  rm -rf "$DOCKER_CONFIG"
}
trap cleanup EXIT

mkdir -p "$BASE_DIR/postgres"
chmod 700 "$BASE_DIR"
if [[ ! -f "$BASE_DIR/.env" ]]; then
  db_password="$(openssl rand -hex 32)"
  jwt_secret="$(openssl rand -hex 48)"
  printf 'POSTGRES_PASSWORD=%s\nJWT_SECRET=%s\n' "$db_password" "$jwt_secret" > "$BASE_DIR/.env"
  chmod 600 "$BASE_DIR/.env"
fi
# The file contains only generated hex secrets and is root-readable only.
source "$BASE_DIR/.env"
DATABASE_URL="postgresql://shop:${POSTGRES_PASSWORD}@postgres:5432/shop"

"${DOCKER[@]}" network inspect "$NETWORK" >/dev/null 2>&1 || "${DOCKER[@]}" network create "$NETWORK" >/dev/null
if ! "${DOCKER[@]}" inspect "$POSTGRES" >/dev/null 2>&1; then
  "${DOCKER[@]}" run -d --name "$POSTGRES" --restart unless-stopped \
    --label retailos.app=shop-database --network "$NETWORK" --network-alias postgres \
    -e POSTGRES_DB=shop -e POSTGRES_USER=shop -e "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
    -v "$BASE_DIR/postgres:/var/lib/postgresql/data" postgres:16-alpine >/dev/null
else
  "${DOCKER[@]}" start "$POSTGRES" >/dev/null 2>&1 || true
  "${DOCKER[@]}" network connect --alias postgres "$NETWORK" "$POSTGRES" >/dev/null 2>&1 || true
fi

ready=false
for attempt in $(seq 1 60); do
  if "${DOCKER[@]}" exec "$POSTGRES" pg_isready -U shop -d shop >/dev/null 2>&1; then ready=true; break; fi
  sleep 2
done
[[ "$ready" == true ]] || { echo "Shop database did not become ready" >&2; exit 1; }

"${DOCKER[@]}" pull "$API_IMAGE"
"${DOCKER[@]}" run --rm --network "$NETWORK" -e "DATABASE_URL=$DATABASE_URL" -e "DIRECT_URL=$DATABASE_URL" \
  --entrypoint npx "$API_IMAGE" prisma migrate deploy

seed_result="$("${DOCKER[@]}" run --rm --network "$NETWORK" -e "DATABASE_URL=$DATABASE_URL" -e "DIRECT_URL=$DATABASE_URL" \
  --entrypoint node "$API_IMAGE" dist/scripts/seed.js Gutagala gutagala)"
# Keep the host deployment script independent of Node.js. The API image has
# already emitted the seed result as JSON; extract the UUID with POSIX tools.
BUSINESS_ID="$(printf '%s\n' "$seed_result" | sed -n 's/.*"businessId":"\([^"]*\)".*/\1/p')"
[[ "$BUSINESS_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "Could not resolve the Gutagala business id" >&2; exit 1; }

# Credentials travel as a short-lived file and are never interpolated into a
# logged command line or retained in the running API container environment.
# The API image runs as the unprivileged `retail` user. Give that UID read-only
# access to the one-shot bind-mounted file; it lives inside the mode-700 temp
# directory and is removed immediately after this command (or by the trap).
RETAIL_UID="$("${DOCKER[@]}" run --rm --entrypoint id "$API_IMAGE" -u retail)"
[[ "$RETAIL_UID" =~ ^[0-9]+$ ]] || { echo "Could not resolve the API container user" >&2; exit 1; }
chown "$RETAIL_UID" "$ADMIN_CONFIG"
chmod 400 "$ADMIN_CONFIG"
"${DOCKER[@]}" run --rm --network "$NETWORK" --mount "type=bind,src=$ADMIN_CONFIG,dst=/run/secrets/super-admin.json,readonly" \
  -e "DATABASE_URL=$DATABASE_URL" -e "DIRECT_URL=$DATABASE_URL" \
  --entrypoint node "$API_IMAGE" dist/scripts/create-super-admin.js /run/secrets/super-admin.json
rm -f "$ADMIN_CONFIG"

"${DOCKER[@]}" pull "$POS_IMAGE"
"${DOCKER[@]}" pull "$WEB_IMAGE"
USED="$( { ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}'; "${DOCKER[@]}" ps -aq | xargs -r "${DOCKER[@]}" inspect --format '{{range $p, $bindings := .HostConfig.PortBindings}}{{range $bindings}}{{.HostPort}}{{"\n"}}{{end}}{{end}}' 2>/dev/null; } | sort -u )"
find_port() {
  local start="$1" end="$2" candidate
  for candidate in $(seq "$start" "$end"); do
    if ! grep -Fxq "$candidate" <<<"$USED"; then
      USED="${USED}${USED:+$'\n'}$candidate"
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}
API_PORT="$(find_port 5100 5599)" || { echo "No free shop API port in 5100-5599" >&2; exit 1; }
POS_PORT="$(find_port 4500 4999)" || { echo "No free POS port in 4500-4999" >&2; exit 1; }
WEB_PORT="$(find_port 5600 5999)" || { echo "No free storefront port in 5600-5999" >&2; exit 1; }

API_NAME="retailpos-api-${DEPLOY_ID}"
POS_NAME="retailpos-${DEPLOY_ID}"
WEB_NAME="retailpos-web-${DEPLOY_ID}"
"${DOCKER[@]}" run -d --name "$API_NAME" --restart unless-stopped \
  --label retailos.app=shop-api --label "retailos.domain=$DOMAIN" \
  --network "$NETWORK" -p "127.0.0.1:${API_PORT}:4000" \
  -e NODE_ENV=production -e PORT=4000 -e "DATABASE_URL=$DATABASE_URL" -e "DIRECT_URL=$DATABASE_URL" \
  -e "JWT_SECRET=$JWT_SECRET" -e "BUSINESS_ID=$BUSINESS_ID" -e "CORS_ORIGIN=https://${DOMAIN}" \
  "$API_IMAGE" >/dev/null
"${DOCKER[@]}" run -d --name "$POS_NAME" --restart unless-stopped \
  --label retailos.app=shop-pos --label "retailos.domain=$DOMAIN" \
  -p "127.0.0.1:${POS_PORT}:8080" "$POS_IMAGE" >/dev/null
"${DOCKER[@]}" run -d --name "$WEB_NAME" --restart unless-stopped \
  --label retailos.app=shop-web --label "retailos.domain=$SHOP_DOMAIN" \
  --network "$NETWORK" -p "127.0.0.1:${WEB_PORT}:3000" "$WEB_IMAGE" >/dev/null

healthy=false
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${API_PORT}/health" >/dev/null \
    && curl -fsS "http://127.0.0.1:${POS_PORT}/" >/dev/null \
    && curl -fsS "http://127.0.0.1:${WEB_PORT}/" >/dev/null; then
    healthy=true
    break
  fi
  sleep 2
done
if [[ "$healthy" != true ]]; then
  "${DOCKER[@]}" logs "$API_NAME" || true
  "${DOCKER[@]}" logs "$POS_NAME" || true
  "${DOCKER[@]}" logs "$WEB_NAME" || true
  "${DOCKER[@]}" rm -f "$API_NAME" "$POS_NAME" "$WEB_NAME" || true
  echo "POS, shop API, or storefront container did not become healthy" >&2
  exit 1
fi

SITE="/etc/nginx/sites-available/$DOMAIN"
sudo tee /etc/nginx/conf.d/retailpos-auth-rate-limit.conf >/dev/null <<'EOF'
limit_req_zone $binary_remote_addr zone=retailpos_auth:10m rate=10r/m;
EOF
sudo tee "$SITE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location = /api/auth/login {
        limit_req zone=retailpos_auth burst=5 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:$API_PORT/auth/login;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:$API_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        proxy_pass http://127.0.0.1:$POS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
server {
    listen 80;
    listen [::]:80;
    server_name $SHOP_DOMAIN www.$SHOP_DOMAIN;
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:$API_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    location / {
        proxy_pass http://127.0.0.1:$WEB_PORT;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
sudo ln -sfn "$SITE" "/etc/nginx/sites-enabled/$DOMAIN"
sudo nginx -t
sudo systemctl reload nginx

if ! command -v certbot >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y certbot python3-certbot-nginx
fi
sudo certbot --nginx --non-interactive --agree-tos --email "$EMAIL" --redirect -d "$DOMAIN"
sudo certbot --nginx --non-interactive --agree-tos --email "$EMAIL" --redirect \
  -d "$SHOP_DOMAIN" -d "www.$SHOP_DOMAIN"
curl -fsSI --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/"
curl -fsS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/health" >/dev/null
for host in "$SHOP_DOMAIN" "www.$SHOP_DOMAIN"; do
  curl -fsSI --resolve "$host:443:127.0.0.1" "https://$host/"
  curl -fsS --resolve "$host:443:127.0.0.1" "https://$host/api/products/storefront" >/dev/null
done

# Retain the previous release until both services and HTTPS are verified.
while IFS= read -r previous; do
  [[ -z "$previous" || "$previous" == "$POS_NAME" ]] || "${DOCKER[@]}" rm -f "$previous"
done < <("${DOCKER[@]}" ps -a --filter "label=retailos.app=shop-pos" --filter "label=retailos.domain=$DOMAIN" --format '{{.Names}}')
while IFS= read -r previous; do
  [[ -z "$previous" || "$previous" == "$API_NAME" ]] || "${DOCKER[@]}" rm -f "$previous"
done < <("${DOCKER[@]}" ps -a --filter "label=retailos.app=shop-api" --filter "label=retailos.domain=$DOMAIN" --format '{{.Names}}')
while IFS= read -r previous; do
  [[ -z "$previous" || "$previous" == "$WEB_NAME" ]] || "${DOCKER[@]}" rm -f "$previous"
done < <("${DOCKER[@]}" ps -a --filter "label=retailos.app=shop-web" --filter "label=retailos.domain=$SHOP_DOMAIN" --format '{{.Names}}')

echo "POS and shop API deployed: https://$DOMAIN; storefront deployed: https://$SHOP_DOMAIN and https://www.$SHOP_DOMAIN"
