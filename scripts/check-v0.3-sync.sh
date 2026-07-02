#!/usr/bin/env bash
set -Eeuo pipefail

echo "Lifly v0.3 sync release checks"

echo "[1/5] git diff whitespace"
git diff --check

echo "[2/5] smoke script syntax"
bash -n scripts/smoke-sync-v0.3.sh

echo "[3/5] API sync tests"
cd services/api
uv run python -m py_compile app/modules/sync/router.py app/modules/sync/schemas.py app/modules/sync/service.py
uv run python -m pytest tests/test_*.py
cd ../..

echo "[4/5] Flutter analyze"
cd apps/client_flutter
flutter analyze

echo "[5/5] Flutter tests"
flutter test

echo "Core v0.3 sync release checks passed."
