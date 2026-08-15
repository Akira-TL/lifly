#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "[FAIL] $label: expected=$expected actual=$actual" >&2
    exit 1
  fi
  echo "[PASS] $label = $actual"
}

assert_eq "$LIFLY_COMMON_POSTGRES_PORT" 8200 "Common PostgreSQL"
assert_eq "$LIFLY_COMMON_REDIS_PORT" 8201 "Common Redis"
assert_eq "$LIFLY_COMMON_MINIO_API_PORT" 8202 "Common MinIO API"
assert_eq "$LIFLY_COMMON_MINIO_CONSOLE_PORT" 8203 "Common MinIO Console"
assert_eq "$LIFLY_COMMON_POWERSYNC_PORT" 8204 "Common PowerSync"

for slot in dev blue green; do
  case "$slot" in
    dev) base=8210 ;;
    blue) base=8240 ;;
    green) base=8270 ;;
  esac
  assert_eq "$(lifly_service_port "$slot" 0)" "$base" "$slot API"
  assert_eq "$(lifly_service_port "$slot" 1)" "$((base + 1))" "$slot Web"
  assert_eq "$(lifly_service_port "$slot" 2)" "$((base + 2))" "$slot MCP reservation"
  assert_eq "$(lifly_service_port "$slot" 3)" "$((base + 3))" "$slot PowerSync reservation"
done

echo "[PASS] PowerSync 使用 Common 8204；各 slot 的 service_id 03 保留为空"
