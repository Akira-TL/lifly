#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "[1/9] API MCP parity and audit tests"
(
  cd services/api
  uv run pytest \
    tests/test_mcp_cloud_local_parity_contract.py \
    tests/test_mcp_ai_audit_security_contract.py \
    tests/test_mcp_capture_commit_service.py \
    tests/test_mcp_capture_undo_contract.py \
    tests/test_mcp_capture_session_contract.py \
    tests/test_mcp_cloud_write_contract.py
)

echo "[2/9] API syntax compile"
(
  cd services/api
  uv run python -m compileall app \
    tests/test_mcp_cloud_local_parity_contract.py \
    tests/test_mcp_ai_audit_security_contract.py \
    tests/test_mcp_capture_commit_service.py \
    tests/test_mcp_capture_undo_contract.py \
    tests/test_mcp_capture_session_contract.py \
    tests/test_mcp_cloud_write_contract.py
)

echo "[3/9] protocol typecheck"
pnpm --filter @lifly/protocol typecheck

echo "[4/9] protocol tests"
pnpm --filter @lifly/protocol test

echo "[5/9] local-core typecheck"
pnpm --filter @lifly/local-core typecheck

echo "[6/9] local-core tests"
pnpm --filter @lifly/local-core test

echo "[7/9] local-mcp typecheck"
pnpm --filter @lifly/local-mcp typecheck

echo "[8/9] local-mcp tests"
pnpm --filter @lifly/local-mcp test

echo "[9/9] Flutter client checks"
bash scripts/check-client-flutter.sh

echo "v0.4 AI Write check passed"
