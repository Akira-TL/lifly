#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[1/3] pnpm typecheck"
pnpm typecheck

echo "[2/3] pnpm test"
pnpm test

echo "[3/3] local mcp smoke"
bash "$ROOT_DIR/scripts/smoke-local-mcp-v0.1.sh"
