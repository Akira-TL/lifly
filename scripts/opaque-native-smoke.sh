#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIBRARY="$PROJECT_ROOT/build/native-opaque/linux/liblifly_opaque_helper.so"

bash "$SCRIPT_DIR/build-native-opaque.sh" linux >/dev/null
(
  cd "$PROJECT_ROOT/apps/client_flutter"
  LIFLY_OPAQUE_NATIVE_LIBRARY="$LIBRARY" dart run tool/opaque_native_smoke.dart
)
