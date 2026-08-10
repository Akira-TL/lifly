#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PORT="${LIFLY_WEB_PORT:-4175}"
PID_FILE="$LOG_DIR/flutter-web-$PORT.pid"

PID=""
if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE")"
else
  PID="$(
    (ss -ltnp 2>/dev/null | grep ":$PORT " |
      sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1) || true
  )"
fi

if [[ -z "$PID" ]]; then
  echo "没有运行中的 Flutter Web 调试实例: port=$PORT"
  exit 0
fi

COMMAND="$(ps -p "$PID" -o args= 2>/dev/null || true)"
if [[ "$COMMAND" != *"flutter_tools.snapshot run -d web-server"* ]] ||
   [[ "$COMMAND" != *"--web-port $PORT"* ]]; then
  echo "端口 $PORT 的进程不是受支持的 Flutter Web 调试实例，拒绝停止。" >&2
  echo "pid=$PID command=$COMMAND" >&2
  exit 1
fi

if kill -0 "$PID" 2>/dev/null; then
  echo "停止 Flutter Web: pid=$PID port=$PORT"
  kill "$PID"
  for _ in $(seq 1 20); do
    if ! kill -0 "$PID" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
fi

rm -f "$PID_FILE"
echo "Flutter Web 已停止: port=$PORT"
