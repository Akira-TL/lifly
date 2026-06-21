#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Lifily - 重启开发环境
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 重启 Lifily 开发环境 ==="

# 停止
"$SCRIPT_DIR/dev-stop.sh"

# 清理数据卷（可选）
if [ "${1:-}" = "--clean" ]; then
  echo "清理数据卷..."
  docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" down -v
fi

# 启动
"$SCRIPT_DIR/dev-start.sh"

echo "=== Lifily 开发环境已重启 ==="
