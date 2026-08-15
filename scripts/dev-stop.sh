#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
API_PID_FILE="$LOG_DIR/api-dev.pid"

export LIFLY_DEPLOY_SLOT=dev
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

echo "=== 停止 Lifly Dev ==="

echo "[1/2] 停止 FastAPI..."
if [[ -f "$API_PID_FILE" ]]; then
  API_PID="$(cat "$API_PID_FILE")"
  COMMAND="$(ps -p "$API_PID" -o args= 2>/dev/null || true)"
  if [[ -n "$COMMAND" ]] && [[ "$COMMAND" == *"fastapi dev app/main.py"* ]] && [[ "$COMMAND" == *"--port $LIFLY_API_PORT"* ]]; then
    kill "$API_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      if ! kill -0 "$API_PID" 2>/dev/null; then
        break
      fi
      sleep 0.25
    done
  elif [[ -n "$COMMAND" ]]; then
    echo "PID $API_PID 不是 Lifly Dev API，拒绝停止：$COMMAND" >&2
  fi
  rm -f "$API_PID_FILE"
else
  echo "  FastAPI 未由 scripts/dev-start.sh 启动"
fi

echo "[2/2] 停止共享 Docker 基础设施..."
docker compose --profile powersync -f "$PROJECT_ROOT/infra/docker-compose.yml" down

echo "=== Lifly Dev 已停止 ==="
