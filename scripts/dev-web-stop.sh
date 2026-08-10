#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PORT="${LIFLY_WEB_PORT:-4175}"
PID_FILE="$LOG_DIR/flutter-web-$PORT.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "没有记录 Flutter Web 调试实例: port=$PORT"
  exit 0
fi

PID="$(cat "$PID_FILE")"
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
