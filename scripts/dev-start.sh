#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Lifly - 启动开发环境
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 启动 Lifly 开发环境 ==="

# 1. Docker 基础设施
echo "[1/3] 启动 Docker 基础设施 (PostgreSQL/Redis/MinIO)..."
docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" up -d postgres redis minio
echo "  PostgreSQL: localhost:8332"
echo "  Redis:      localhost:8379"
echo "  MinIO API:  localhost:8300"
echo "  MinIO CUI:  localhost:8301"

# 2. FastAPI 后端
echo "[2/3] 启动 FastAPI 后端 (port 8310)..."
cd "$PROJECT_ROOT/services/api"
uv run fastapi dev app/main.py --port 8310 --host 0.0.0.0 &
API_PID=$!
echo "  FastAPI PID: $API_PID"
echo "  API: http://localhost:8310"
echo "  Docs: http://localhost:8310/docs"

# 3. 等待就绪
echo "[3/3] 等待服务就绪..."
sleep 2

echo ""
echo "=== Lifly 开发环境已启动 ==="
echo "API:      http://localhost:8310"
echo "Docs:     http://localhost:8310/docs"
echo "MinIO:    http://localhost:8301"
echo ""
echo "停止: kill $API_PID && docker compose -f infra/docker-compose.yml down"
