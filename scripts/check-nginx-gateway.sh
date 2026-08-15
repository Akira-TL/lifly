#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="${LIFLY_PUBLIC_DOMAIN:-lifly.babelbeast.com}"

bash "$PROJECT_ROOT/infra/gateway/deploy-nginx.sh" --check

if [[ -e "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
  curl -fsS --max-time 10 "https://$DOMAIN/" >/dev/null
  curl -fsS --max-time 10 "https://$DOMAIN/api/v1/health" >/dev/null
  echo "[PASS] HTTPS Web/API: $DOMAIN"
else
  echo "[INFO] 证书尚未签发；运行 bash scripts/deploy-nginx.sh apply"
fi
