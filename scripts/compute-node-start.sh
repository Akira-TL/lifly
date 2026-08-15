#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/compute-node-worker.log"

if [[ -t 0 ]]; then
  cat >&2 <<'EOF'
Compute Node worker 需要从 stdin 接收一次性 JSON 凭据，不会从环境变量或文件读取设备私钥/access token。
字段：account_id, account_data_key_base64, 可选 account_data_key_version, device_id, private_key_base64, access_token, 可选 api_base_url。
EOF
  exit 2
fi

if [[ -z "${LIFLY_LOCAL_CORE_BRIDGE_PATH:-}" ]]; then
  echo "LIFLY_LOCAL_CORE_BRIDGE_PATH 未配置，无法启动真实 Desktop Local Core Bridge" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
export LIFLY_AI_PROVIDER_HELPER_PATH="${LIFLY_AI_PROVIDER_HELPER_PATH:-$PROJECT_ROOT/scripts/ai-provider-worker.sh}"
export LIFLY_LOCAL_AI_ENDPOINT="${LIFLY_LOCAL_AI_ENDPOINT:-http://127.0.0.1:8205}"
export LIFLY_LOCAL_AI_MODEL="${LIFLY_LOCAL_AI_MODEL:-${LIFLY_CLOUD_AI_MODEL:-}}"
cd "$PROJECT_ROOT"
pnpm --dir services/local-mcp build

echo "启动 Lifly encrypted Compute Node worker；运行日志：$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1
exec node "$PROJECT_ROOT/services/local-mcp/dist/services/local-mcp/src/relay-worker-main.js"
