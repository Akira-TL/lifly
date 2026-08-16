#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROVIDER_DIR="${LIFLY_AI_PROVIDER_PROJECT_DIR:-$PROJECT_ROOT/services/api}"

if [[ ! -f "$PROVIDER_DIR/pyproject.toml" ]]; then
  echo "Lifly AI provider project unavailable: $PROVIDER_DIR" >&2
  exit 2
fi
cd "$PROVIDER_DIR"
exec uv run python -m app.modules.ai.provider_worker
