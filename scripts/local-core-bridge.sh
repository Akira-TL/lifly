#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE="$PROJECT_ROOT/apps/client_flutter/build/runtime/local-core-bridge"
BINARY="$BUNDLE/client_flutter"
if [[ ! -x "$BINARY" ]]; then
  echo "Lifly Local Core bridge 未构建；先运行 bash scripts/build-runtime-helpers.sh" >&2
  exit 2
fi
exec "$BINARY"
