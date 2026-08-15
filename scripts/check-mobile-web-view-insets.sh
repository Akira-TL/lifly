#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LIFLY_DEPLOY_SLOT=dev
# shellcheck source=scripts/lib/lifly-ports.sh
source "$ROOT_DIR/scripts/lib/lifly-ports.sh"
export LIFLY_WEB_URL="http://127.0.0.1:$LIFLY_WEB_PORT/"

node "$ROOT_DIR/scripts/check-mobile-web-view-insets.mjs"
