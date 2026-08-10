#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"
LOG_DIR="$PROJECT_ROOT/logs"

PORT="${LIFLY_WEB_PORT:-4175}"
DATA_MODE="${LIFLY_DATA_MODE:-local}"
API_BASE_URL="${LIFLY_API_BASE_URL:-http://127.0.0.1:8310/api/v1}"
APP_VERSION="${LIFLY_APP_VERSION:-0.8.2}"
PID_FILE="$LOG_DIR/flutter-web-$PORT.pid"
LOG_FILE="$LOG_DIR/flutter-web-$PORT.log"

mkdir -p "$LOG_DIR"

if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" 2>/dev/null; then
    echo "Flutter Web 已运行: pid=$PID port=$PORT"
    echo "日志: $LOG_FILE"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

if ss -ltn | grep -q ":$PORT "; then
  echo "端口 $PORT 已被其他进程占用" >&2
  exit 1
fi

echo "启动 Flutter Web 调试实例..."
echo "  URL:      http://127.0.0.1:$PORT"
echo "  DataMode: $DATA_MODE"
echo "  API:      $API_BASE_URL"
echo "  Log:      $LOG_FILE"

cd "$CLIENT_DIR"
nohup flutter run -d web-server \
  --web-hostname 0.0.0.0 \
  --web-port "$PORT" \
  --dart-define="LIFLY_DATA_MODE=$DATA_MODE" \
  --dart-define="LIFLY_API_BASE_URL=$API_BASE_URL" \
  --dart-define="LIFLY_APP_VERSION=$APP_VERSION" \
  >"$LOG_FILE" 2>&1 < /dev/null &
PID=$!
printf '%s\n' "$PID" > "$PID_FILE"

for _ in $(seq 1 90); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT" >/dev/null 2>&1; then
    echo "Flutter Web 已就绪: pid=$PID port=$PORT"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Flutter Web 启动失败，最近日志：" >&2
    tail -n 80 "$LOG_FILE" >&2 || true
    rm -f "$PID_FILE"
    exit 1
  fi
  sleep 1
done

echo "Flutter Web 在 90 秒内未就绪，最近日志：" >&2
tail -n 80 "$LOG_FILE" >&2 || true
exit 1
