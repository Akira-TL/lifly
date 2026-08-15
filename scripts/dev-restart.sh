#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Lifly - 重启开发环境
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 重启 Lifly 开发环境 ==="

# 停止
"$SCRIPT_DIR/dev-stop.sh"

# 清理数据卷（可选）。端口迁移后沿用历史数据卷名，需显式重建。
if [ "${1:-}" = "--clean" ]; then
  echo "清理 Lifly 数据卷..."
  docker volume rm infra_lifly_postgres infra_lifly_minio 2>/dev/null || true
  docker volume create infra_lifly_postgres >/dev/null
  docker volume create infra_lifly_minio >/dev/null
fi

# 启动
"$SCRIPT_DIR/dev-start.sh"

echo "=== Lifly 开发环境已重启 ==="
