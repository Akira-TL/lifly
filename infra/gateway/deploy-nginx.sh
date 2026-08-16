#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOMAIN="${LIFLY_PUBLIC_DOMAIN:-lifly.babelbeast.com}"
NGINX_CONFIG="${NGINX_CONFIG:-/etc/nginx/nginx.conf}"
WEBROOT="${CERTBOT_WEBROOT:-/var/www/html}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/nginx}"
CERTBOT_HOOK="${CERTBOT_HOOK:-/etc/letsencrypt/renewal-hooks/deploy/lifly-reload-nginx}"
PROJECT_INCLUDE="    include $PROJECT_ROOT/infra/gateway/sites-enabled/*.conf;"
HTTPS_LINK="$SCRIPT_DIR/sites-enabled/lifly-https.conf"
HTTPS_TARGET="$SCRIPT_DIR/sites/lifly-https.conf"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
MODE="${1:-apply}"

case "$MODE" in
  apply | --check) ;;
  *)
    printf '用法：%s [apply|--check]\n' "$0" >&2
    exit 2
    ;;
esac

if [[ ${EUID} -ne 0 ]]; then
  exec sudo --preserve-env=LIFLY_PUBLIC_DOMAIN,NGINX_CONFIG,CERTBOT_WEBROOT,BACKUP_ROOT,CERTBOT_HOOK,CERTBOT_EMAIL -- /usr/bin/env bash "$0" "$@"
fi

for command_name in nginx systemctl certbot install cp grep date mkdir ln rm python3; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf '缺少命令：%s\n' "$command_name" >&2
    exit 1
  }
done

for required in \
  "$SCRIPT_DIR/sites/lifly-http.conf" \
  "$SCRIPT_DIR/sites/lifly-https.conf" \
  "$SCRIPT_DIR/sites-enabled/lifly-http.conf" \
  "$SCRIPT_DIR/reload-nginx-after-renewal.sh"; do
  [[ -f "$required" ]] || {
    printf '缺少 Lifly Gateway 文件：%s\n' "$required" >&2
    exit 1
  }
done

if [[ "$MODE" == --check ]]; then
  bash -n "$SCRIPT_DIR/deploy-nginx.sh"
  bash -n "$SCRIPT_DIR/reload-nginx-after-renewal.sh"
  grep -Fq 'server_name lifly.babelbeast.com;' "$SCRIPT_DIR/sites/lifly-http.conf"
  grep -Fq 'root /home/Akira/Projects/lifly/apps/client_flutter/build/web;' "$SCRIPT_DIR/sites/lifly-https.conf"
  grep -Fq 'proxy_pass http://127.0.0.1:8210;' "$SCRIPT_DIR/sites/lifly-https.conf"
  if grep -Fq "$PROJECT_INCLUDE" "$NGINX_CONFIG"; then
    nginx -t
  fi
  printf 'Lifly Gateway 配置检查通过。\n'
  exit 0
fi

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="$BACKUP_ROOT/lifly-$stamp"
mkdir -p "$backup_dir"
cp -a "$NGINX_CONFIG" "$backup_dir/nginx.conf"

had_https_link=false
[[ -e "$HTTPS_LINK" || -L "$HTTPS_LINK" ]] && had_https_link=true

rollback() {
  local exit_code=$?
  trap - ERR
  printf 'Lifly Gateway 部署失败，恢复 Nginx 全局配置：%s\n' "$backup_dir/nginx.conf" >&2
  cp -a "$backup_dir/nginx.conf" "$NGINX_CONFIG"
  if [[ "$had_https_link" == false ]]; then
    rm -f "$HTTPS_LINK"
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx || true
  exit "$exit_code"
}
trap rollback ERR

# Add exactly one project include without replacing PeTalk/BondNote/other project includes.
if ! grep -Fqx "$PROJECT_INCLUDE" "$NGINX_CONFIG"; then
  PROJECT_INCLUDE="$PROJECT_INCLUDE" NGINX_CONFIG="$NGINX_CONFIG" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["NGINX_CONFIG"])
include_line = os.environ["PROJECT_INCLUDE"]
text = path.read_text()
if include_line not in text:
    stripped = text.rstrip()
    if not stripped.endswith("}"):
        raise SystemExit("nginx.conf does not end with an http block closing brace")
    stripped = stripped[:-1].rstrip()
    path.write_text(f"{stripped}\n{include_line}\n}}\n")
PY
fi

mkdir -p "$WEBROOT"

# Phase 1 is needed only for first-time HTTP-01 issuance. Once a certificate
# exists, keep HTTPS active and perform a single validated reload at the end.
if [[ ! -s "$CERT_DIR/fullchain.pem" || ! -s "$CERT_DIR/privkey.pem" ]]; then
  rm -f "$HTTPS_LINK"
  nginx -t
  systemctl reload nginx

  certbot_args=(
    certonly
    --webroot
    -w "$WEBROOT"
    -d "$DOMAIN"
    --non-interactive
    --agree-tos
    --keep-until-expiring
    --preferred-challenges http
  )

  # Existing Certbot accounts need no new email. Fresh hosts must provide one explicitly.
  if ! find /etc/letsencrypt/accounts -type f -name regr.json -print -quit 2>/dev/null | grep -q .; then
    if [[ -z "${CERTBOT_EMAIL:-}" ]]; then
      printf '首次 Certbot 注册需要 CERTBOT_EMAIL，例如：CERTBOT_EMAIL=you@example.com %s apply\n' "$0" >&2
      false
    fi
    certbot_args+=(--email "$CERTBOT_EMAIL")
  fi

  certbot "${certbot_args[@]}"
fi

# Phase 2: certificate exists; enable the version-controlled HTTPS site from the project tree.
ln -sfn ../sites/lifly-https.conf "$HTTPS_LINK"
install -D -m 0755 "$SCRIPT_DIR/reload-nginx-after-renewal.sh" "$CERTBOT_HOOK"
systemctl enable --now certbot.timer >/dev/null

nginx -t
systemctl reload nginx
systemctl is-active --quiet nginx
systemctl is-active --quiet certbot.timer

trap - ERR
printf 'Lifly Nginx 已启用：https://%s\n' "$DOMAIN"
printf 'Web -> project release bundle\n'
printf 'API/MCP -> 127.0.0.1:8210\n'
printf 'Certbot renewal timer: active\n'
printf 'Nginx 备份：%s\n' "$backup_dir"
