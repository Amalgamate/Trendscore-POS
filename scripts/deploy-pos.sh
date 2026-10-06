#!/usr/bin/env bash
set -euo pipefail

IMAGE="${1:?image reference required}"
DOMAIN="${2:?domain required}"
EMAIL="${3:?certificate email required}"
DEPLOY_ID="${4:?deploy id required}"
DOCKER_CONFIG="${DOCKER_CONFIG:?temporary Docker config required}"

[[ "$IMAGE" =~ ^ghcr\.io/[a-z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] || { echo "Invalid image reference" >&2; exit 2; }
[[ "$DOMAIN" =~ ^[a-z0-9.-]+$ ]] || { echo "Invalid domain" >&2; exit 2; }
[[ "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || { echo "Invalid certificate email" >&2; exit 2; }
[[ "$DEPLOY_ID" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Invalid deploy id" >&2; exit 2; }

DOCKER=(docker --config "$DOCKER_CONFIG")
if ! docker info >/dev/null 2>&1; then
  DOCKER=(sudo docker --config "$DOCKER_CONFIG")
fi
trap 'rm -rf "$DOCKER_CONFIG"' EXIT

"${DOCKER[@]}" pull "$IMAGE"

# Match the host's established frontend allocation scheme and avoid both
# host listeners and Docker-published ports.
USED="$( { ss -ltnH 2>/dev/null | awk '{n=split($4,a,":"); print a[n]}'; "${DOCKER[@]}" ps -aq | xargs -r "${DOCKER[@]}" inspect --format '{{range $p, $bindings := .HostConfig.PortBindings}}{{range $bindings}}{{.HostPort}}{{"\n"}}{{end}}{{end}}' 2>/dev/null; } | sort -u )"
PORT=""
for candidate in $(seq 4500 4999); do
  if ! grep -Fxq "$candidate" <<<"$USED"; then PORT="$candidate"; break; fi
done
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "No free POS frontend port in 4500-4999" >&2; exit 1; }

NAME="retailpos-${DEPLOY_ID}"
"${DOCKER[@]}" rm -f "$NAME" >/dev/null 2>&1 || true
"${DOCKER[@]}" run -d --name "$NAME" --restart unless-stopped \
  --label retailos.app=shop-pos --label "retailos.domain=$DOMAIN" \
  -p "127.0.0.1:${PORT}:8080" "$IMAGE" >/dev/null

healthy=false
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null; then healthy=true; break; fi
  sleep 2
done
if [[ "$healthy" != true ]]; then
  "${DOCKER[@]}" logs "$NAME" || true
  "${DOCKER[@]}" rm -f "$NAME" || true
  echo "POS container did not become healthy" >&2
  exit 1
fi

SITE="/etc/nginx/sites-available/$DOMAIN"
sudo tee "$SITE" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
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
curl -fsSI --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/"

# Keep the currently served container until the new route and certificate work.
while IFS= read -r previous; do
  [[ -z "$previous" || "$previous" == "$NAME" ]] || "${DOCKER[@]}" rm -f "$previous"
done < <("${DOCKER[@]}" ps -a --filter "label=retailos.app=shop-pos" --filter "label=retailos.domain=$DOMAIN" --format '{{.Names}}')

echo "POS deployed: https://$DOMAIN (127.0.0.1:$PORT)"
