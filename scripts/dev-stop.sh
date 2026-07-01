#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Lifly - 停止开发环境
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 停止 Lifly 开发环境 ==="

# 停止 FastAPI
echo "[1/2] 停止 FastAPI 后端..."
pkill -f "fastapi dev app/main.py" 2>/dev/null || echo "  (FastAPI 未运行)"

# 停止 Docker 基础设施
echo "[2/2] 停止 Docker 基础设施..."
docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" down
echo "  Docker 服务已停止"

echo "=== Lifly 开发环境已停止 ==="
