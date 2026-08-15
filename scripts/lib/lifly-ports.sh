#!/usr/bin/env bash
# Lifly 宿主机端口命名空间。容器内部端口不受此文件约束。

LIFLY_PROJECT_PORT_BASE=8200
LIFLY_COMMON_POSTGRES_PORT=8200
LIFLY_COMMON_REDIS_PORT=8201
LIFLY_COMMON_MINIO_API_PORT=8202
LIFLY_COMMON_MINIO_CONSOLE_PORT=8203
LIFLY_COMMON_POWERSYNC_PORT=8204
LIFLY_COMMON_OLLAMA_PORT=8205

lifly_slot_offset() {
  case "${1:?slot is required}" in
    dev) printf '%s\n' 10 ;;
    blue) printf '%s\n' 40 ;;
    green) printf '%s\n' 70 ;;
    *)
      echo "不支持的 Lifly deployment slot: $1（仅支持 dev/blue/green）" >&2
      return 2
      ;;
  esac
}

lifly_service_port() {
  local slot="${1:?slot is required}"
  local service_id="${2:?service_id is required}"

  if [[ ! "$service_id" =~ ^[0-9]+$ ]] || (( service_id < 0 || service_id > 29 )); then
    echo "Lifly service_id 必须是 0-29: $service_id" >&2
    return 2
  fi

  local offset
  offset="$(lifly_slot_offset "$slot")"
  printf '%s\n' "$((LIFLY_PROJECT_PORT_BASE + offset + service_id))"
}

LIFLY_DEPLOY_SLOT="${LIFLY_DEPLOY_SLOT:-dev}"
LIFLY_API_PORT="$(lifly_service_port "$LIFLY_DEPLOY_SLOT" 0)"
LIFLY_WEB_PORT="$(lifly_service_port "$LIFLY_DEPLOY_SLOT" 1)"
LIFLY_MCP_RESERVED_PORT="$(lifly_service_port "$LIFLY_DEPLOY_SLOT" 2)"
LIFLY_SLOT_POWERSYNC_RESERVED_PORT="$(lifly_service_port "$LIFLY_DEPLOY_SLOT" 3)"
LIFLY_POWERSYNC_PORT="$LIFLY_COMMON_POWERSYNC_PORT"

export \
  LIFLY_PROJECT_PORT_BASE \
  LIFLY_DEPLOY_SLOT \
  LIFLY_COMMON_POSTGRES_PORT \
  LIFLY_COMMON_REDIS_PORT \
  LIFLY_COMMON_MINIO_API_PORT \
  LIFLY_COMMON_MINIO_CONSOLE_PORT \
  LIFLY_COMMON_POWERSYNC_PORT \
  LIFLY_COMMON_OLLAMA_PORT \
  LIFLY_API_PORT \
  LIFLY_WEB_PORT \
  LIFLY_MCP_RESERVED_PORT \
  LIFLY_SLOT_POWERSYNC_RESERVED_PORT \
  LIFLY_POWERSYNC_PORT
