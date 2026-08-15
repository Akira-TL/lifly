#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
API_PID_FILE="$LOG_DIR/api-dev.pid"
API_LOG_FILE="$LOG_DIR/api-dev.log"

export LIFLY_DEPLOY_SLOT=dev
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

mkdir -p "$LOG_DIR"

LIFLY_ENABLE_POWERSYNC="${LIFLY_ENABLE_POWERSYNC:-true}"
LIFLY_ENABLE_OLLAMA="${LIFLY_ENABLE_OLLAMA:-true}"

echo "=== 启动 Lifly Dev ==="
echo "[1/4] 启动共享基础设施 (PostgreSQL/Redis/MinIO)..."
docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" up -d postgres redis minio

echo "  PostgreSQL: 127.0.0.1:$LIFLY_COMMON_POSTGRES_PORT"
echo "  Redis:      127.0.0.1:$LIFLY_COMMON_REDIS_PORT"
echo "  MinIO API:  http://127.0.0.1:$LIFLY_COMMON_MINIO_API_PORT"
echo "  MinIO UI:   http://127.0.0.1:$LIFLY_COMMON_MINIO_CONSOLE_PORT"
if [[ "$LIFLY_ENABLE_POWERSYNC" == "true" ]]; then
  echo "  PowerSync:  启动共享实例 http://127.0.0.1:$LIFLY_COMMON_POWERSYNC_PORT"
  docker compose --profile powersync -f "$PROJECT_ROOT/infra/docker-compose.yml" up -d powersync
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 1 "http://127.0.0.1:$LIFLY_COMMON_POWERSYNC_PORT/probes/liveness" >/dev/null 2>&1; then
      echo "  PowerSync:  已就绪"
      break
    fi
    POWERSYNC_CONTAINER_ID="$(docker compose --profile powersync -f "$PROJECT_ROOT/infra/docker-compose.yml" ps -aq powersync)"
    if [[ -n "$POWERSYNC_CONTAINER_ID" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "$POWERSYNC_CONTAINER_ID" 2>/dev/null || true)" != "true" ]]; then
      echo "PowerSync 启动失败，最近日志：" >&2
      docker compose --profile powersync -f "$PROJECT_ROOT/infra/docker-compose.yml" logs --tail 80 powersync >&2 || true
      exit 1
    fi
    sleep 1
  done
  if ! curl -fsS --max-time 1 "http://127.0.0.1:$LIFLY_COMMON_POWERSYNC_PORT/probes/liveness" >/dev/null 2>&1; then
    echo "PowerSync 在 30 秒内未就绪" >&2
    docker compose --profile powersync -f "$PROJECT_ROOT/infra/docker-compose.yml" logs --tail 80 powersync >&2 || true
    exit 1
  fi
else
  echo "  PowerSync:  已显式禁用（共享端口保留为 $LIFLY_COMMON_POWERSYNC_PORT）"
fi

echo "[2/4] 启动 Ollama runtime..."
if [[ "$LIFLY_ENABLE_OLLAMA" == "true" ]]; then
  docker compose --profile ai -f "$PROJECT_ROOT/infra/docker-compose.yml" up -d ollama
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 1 "http://127.0.0.1:$LIFLY_COMMON_OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
      echo "  Ollama:     已就绪 http://127.0.0.1:$LIFLY_COMMON_OLLAMA_PORT"
      break
    fi
    sleep 1
  done
  if ! curl -fsS --max-time 1 "http://127.0.0.1:$LIFLY_COMMON_OLLAMA_PORT/api/tags" >/dev/null 2>&1; then
    echo "Ollama 在 60 秒内未就绪" >&2
    docker compose --profile ai -f "$PROJECT_ROOT/infra/docker-compose.yml" logs --tail 80 ollama >&2 || true
    exit 1
  fi
else
  echo "  Ollama:     已显式禁用（共享端口保留为 $LIFLY_COMMON_OLLAMA_PORT）"
fi

echo "[3/4] 启动 FastAPI Dev (port $LIFLY_API_PORT)..."
if [[ -f "$API_PID_FILE" ]]; then
  previous_pid="$(cat "$API_PID_FILE")"
  previous_command="$(ps -p "$previous_pid" -o args= 2>/dev/null || true)"
  if [[ -n "$previous_command" ]] &&
     [[ "$previous_command" == *"fastapi dev app/main.py"* ]] &&
     [[ "$previous_command" == *"--port $LIFLY_API_PORT"* ]]; then
    echo "FastAPI 已运行: pid=$previous_pid port=$LIFLY_API_PORT"
  else
    rm -f "$API_PID_FILE"
  fi
fi

if [[ ! -f "$API_PID_FILE" ]]; then
  if ss -ltn | grep -q ":$LIFLY_API_PORT "; then
    echo "端口 $LIFLY_API_PORT 已被其他进程占用" >&2
    exit 1
  fi

  cd "$PROJECT_ROOT/services/api"
  nohup env \
    API_PORT="$LIFLY_API_PORT" \
    DATABASE_URL="postgresql+asyncpg://lifly:lifly@127.0.0.1:$LIFLY_COMMON_POSTGRES_PORT/lifly" \
    REDIS_URL="redis://127.0.0.1:$LIFLY_COMMON_REDIS_PORT/0" \
    MINIO_ENDPOINT="http://127.0.0.1:$LIFLY_COMMON_MINIO_API_PORT" \
    POWERSYNC_URL="http://127.0.0.1:$LIFLY_COMMON_POWERSYNC_PORT" \
    LIFLY_CLOUD_AI_PROVIDER="${LIFLY_CLOUD_AI_PROVIDER:-ollama}" \
    LIFLY_CLOUD_AI_ENDPOINT="${LIFLY_CLOUD_AI_ENDPOINT:-http://127.0.0.1:$LIFLY_COMMON_OLLAMA_PORT}" \
    LIFLY_CLOUD_AI_MODEL="${LIFLY_CLOUD_AI_MODEL:-}" \
    uv run fastapi dev app/main.py --port "$LIFLY_API_PORT" --host 127.0.0.1 \
    >"$API_LOG_FILE" 2>&1 < /dev/null &
  API_PID=$!
  printf '%s\n' "$API_PID" > "$API_PID_FILE"
  echo "  FastAPI PID: $API_PID"
fi

echo "[4/4] 等待 API 就绪..."
for _ in $(seq 1 60); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$LIFLY_API_PORT/api/v1/health" >/dev/null 2>&1; then
    echo "=== Lifly Dev 已启动 ==="
    echo "API:      http://127.0.0.1:$LIFLY_API_PORT"
    echo "Docs:     http://127.0.0.1:$LIFLY_API_PORT/docs"
    echo "Web:      使用 scripts/dev-web-start.sh 启动 http://127.0.0.1:$LIFLY_WEB_PORT"
    echo "日志:     $API_LOG_FILE"
    exit 0
  fi

  if [[ -f "$API_PID_FILE" ]]; then
    current_pid="$(cat "$API_PID_FILE")"
    if ! kill -0 "$current_pid" 2>/dev/null; then
      echo "FastAPI 启动失败，最近日志：" >&2
      tail -n 80 "$API_LOG_FILE" >&2 || true
      rm -f "$API_PID_FILE"
      exit 1
    fi
  fi
  sleep 1
done

echo "FastAPI 在 60 秒内未就绪，最近日志：" >&2
tail -n 80 "$API_LOG_FILE" >&2 || true
exit 1
