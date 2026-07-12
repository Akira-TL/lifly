#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API_DIR="$ROOT_DIR/services/api"

cd "$API_DIR"

if [[ "${LIFLY_INCLUDE_API_INTEGRATION:-0}" == "1" ]]; then
  echo "[1/1] uv run pytest"
  uv run pytest
else
  echo "[1/1] uv run pytest tests --ignore=tests/integration"
  uv run pytest tests --ignore=tests/integration
fi
