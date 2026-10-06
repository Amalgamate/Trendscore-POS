#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_HOST:?DEPLOY_HOST secret is required}"
: "${DEPLOY_USER:?DEPLOY_USER secret is required}"
: "${DEPLOY_SSH_KEY:?DEPLOY_SSH_KEY secret is required}"

host="${DEPLOY_HOST#http://}"
host="${host#https://}"
host="${host%%/*}"
[[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Invalid deployment host" >&2; exit 2; }
[[ "$DEPLOY_USER" =~ ^[a-zA-Z0-9._-]+$ ]] || { echo "Invalid deployment user" >&2; exit 2; }

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s\n' "$DEPLOY_SSH_KEY" > "$HOME/.ssh/deploy_key"
chmod 600 "$HOME/.ssh/deploy_key"
cat > "$HOME/.ssh/config" <<EOF
Host production
  HostName $host
  User $DEPLOY_USER
  IdentityFile ~/.ssh/deploy_key
  IdentitiesOnly yes
  BatchMode yes
  StrictHostKeyChecking accept-new
  ConnectTimeout 20
  ConnectionAttempts 1
  ServerAliveInterval 15
  ServerAliveCountMax 4
EOF
chmod 600 "$HOME/.ssh/config"
ssh production true
