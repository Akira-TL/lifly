#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/apps/client_flutter"
BUILD_ROOT="$CLIENT_DIR/build/theme-performance"
DEFAULT_BUILD="$BUILD_ROOT/default"
WASM_BUILD="$BUILD_ROOT/wasm"
REPORT_FILE="$BUILD_ROOT/report.json"

JS_MAX_BYTES="${LIFLY_WEB_JS_MAX_BYTES:-8388608}"
APP_WASM_MAX_BYTES="${LIFLY_WEB_APP_WASM_MAX_BYTES:-8388608}"
RENDERER_WASM_MAX_BYTES="${LIFLY_WEB_RENDERER_WASM_MAX_BYTES:-10485760}"
HOST_MAX_BYTES="${LIFLY_WEB_HOST_MAX_BYTES:-32768}"
SQLITE_WASM_MIN_BYTES="${LIFLY_SQLITE_WASM_MIN_BYTES:-1000000}"
POWERSYNC_DB_WORKER_MIN_BYTES="${LIFLY_POWERSYNC_DB_WORKER_MIN_BYTES:-250000}"
POWERSYNC_SYNC_WORKER_MIN_BYTES="${LIFLY_POWERSYNC_SYNC_WORKER_MIN_BYTES:-300000}"
REUSE_BUILDS="${LIFLY_WEB_REUSE_BUILDS:-0}"
APP_VERSION="${LIFLY_APP_VERSION:-0.8.1}"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

file_size() {
  stat -c '%s' "$1"
}

assert_max_size() {
  local label="$1"
  local path="$2"
  local budget="$3"
  [[ -f "$path" ]] || fail "$label missing: $path"
  local size
  size="$(file_size "$path")"
  (( size <= budget )) || fail "$label is ${size} bytes, budget is ${budget}"
  echo "[PASS] $label ${size}/${budget} bytes"
}

assert_min_size() {
  local label="$1"
  local path="$2"
  local minimum="$3"
  [[ -f "$path" ]] || fail "$label missing: $path"
  local size
  size="$(file_size "$path")"
  (( size >= minimum )) || fail "$label is ${size} bytes, expected at least ${minimum}"
  echo "[PASS] $label ${size} bytes"
}

cd "$CLIENT_DIR"
if [[ "$REUSE_BUILDS" != "1" ]]; then
  rm -rf "$BUILD_ROOT"
fi
mkdir -p "$BUILD_ROOT"

for mark in \
  lifly-host-feedback \
  lifly-entrypoint-loaded \
  lifly-engine-initialized \
  lifly-flutter-first-frame \
  lifly-core-usable \
  lifly-theme-activated; do
  rg -q "$mark" web lib/app/startup || fail "startup mark missing: $mark"
done

rg -Fq 'id="lifly-startup-shell"' web/index.html || fail "startup shell missing"
rg -Fq '{{flutter_js}}' web/flutter_bootstrap.js || fail "flutter_js token missing"
rg -Fq '{{flutter_build_config}}' web/flutter_bootstrap.js || fail "flutter_build_config token missing"
rg -q '_flutter\.loader\.load' web/flutter_bootstrap.js || fail "custom loader missing"
assert_min_size 'PowerSync sqlite3.wasm source asset' \
  web/sqlite3.wasm "$SQLITE_WASM_MIN_BYTES"
assert_min_size 'PowerSync database worker source asset' \
  web/powersync_db.worker.js "$POWERSYNC_DB_WORKER_MIN_BYTES"
assert_min_size 'PowerSync sync worker source asset' \
  web/powersync_sync.worker.js "$POWERSYNC_SYNC_WORKER_MIN_BYTES"
(
  cd web
  sha256sum -c powersync-assets.sha256
) || fail "PowerSync Web source asset checksum mismatch"
if rg -q 'https?://|AssetImage|NetworkImage' lib/app/theme/app_theme.dart ||
  rg -q "fontFamily: [\"']" lib/app/theme/app_theme.dart; then
  fail "Lifly Core gained a remote, font, or decorative asset dependency"
fi

echo '[1/4] Flutter static and security checks'
flutter analyze
flutter test \
  test/web_startup_contract_test.dart \
  test/powersync_schema_test.dart \
  test/powersync_initialization_diagnostics_test.dart \
  test/theme_cache_bootstrapper_test.dart \
  test/theme_manifest_test.dart \
  test/theme_package_store_test.dart

default_started=0
default_finished=0
wasm_started=0
wasm_finished=0
if [[ "$REUSE_BUILDS" == "1" ]]; then
  [[ -d "$DEFAULT_BUILD" ]] || fail "Reusable default build is missing"
  [[ -d "$WASM_BUILD" ]] || fail "Reusable Wasm build is missing"
  echo '[2/4] Reusing existing Default Web build'
  echo '[3/4] Reusing existing WebAssembly Web build'
else
  echo '[2/4] Default Web build'
  default_started="$(date +%s%3N)"
  flutter build web \
    --release \
    --no-source-maps \
    --output "$DEFAULT_BUILD" \
    --dart-define=LIFLY_APP_VERSION="$APP_VERSION"
  default_finished="$(date +%s%3N)"

  echo '[3/4] WebAssembly Web build'
  wasm_started="$(date +%s%3N)"
  flutter build web \
    --release \
    --wasm \
    --no-source-maps \
    --output "$WASM_BUILD" \
    --dart-define=LIFLY_APP_VERSION="$APP_VERSION"
  wasm_finished="$(date +%s%3N)"
fi

echo '[4/4] Artifact budgets'
assert_max_size 'Default main.dart.js' "$DEFAULT_BUILD/main.dart.js" "$JS_MAX_BYTES"
assert_max_size 'Default index.html' "$DEFAULT_BUILD/index.html" "$HOST_MAX_BYTES"
assert_max_size 'Default flutter_bootstrap.js' "$DEFAULT_BUILD/flutter_bootstrap.js" "$HOST_MAX_BYTES"
assert_min_size 'Default PowerSync sqlite3.wasm' \
  "$DEFAULT_BUILD/sqlite3.wasm" "$SQLITE_WASM_MIN_BYTES"
assert_min_size 'Default PowerSync database worker' \
  "$DEFAULT_BUILD/powersync_db.worker.js" "$POWERSYNC_DB_WORKER_MIN_BYTES"
assert_min_size 'Default PowerSync sync worker' \
  "$DEFAULT_BUILD/powersync_sync.worker.js" "$POWERSYNC_SYNC_WORKER_MIN_BYTES"
(
  cd "$DEFAULT_BUILD"
  sha256sum -c "$CLIENT_DIR/web/powersync-assets.sha256"
) || fail "Default build PowerSync asset checksum mismatch"

app_wasm="$WASM_BUILD/main.dart.wasm"
renderer_wasm="$WASM_BUILD/canvaskit/canvaskit.wasm"
assert_max_size 'Application main.dart.wasm' "$app_wasm" "$APP_WASM_MAX_BYTES"
assert_max_size 'Shared CanvasKit renderer Wasm' "$renderer_wasm" "$RENDERER_WASM_MAX_BYTES"
assert_max_size 'Wasm index.html' "$WASM_BUILD/index.html" "$HOST_MAX_BYTES"
assert_max_size 'Wasm flutter_bootstrap.js' "$WASM_BUILD/flutter_bootstrap.js" "$HOST_MAX_BYTES"
assert_min_size 'Wasm PowerSync sqlite3.wasm' \
  "$WASM_BUILD/sqlite3.wasm" "$SQLITE_WASM_MIN_BYTES"
assert_min_size 'Wasm PowerSync database worker' \
  "$WASM_BUILD/powersync_db.worker.js" "$POWERSYNC_DB_WORKER_MIN_BYTES"
assert_min_size 'Wasm PowerSync sync worker' \
  "$WASM_BUILD/powersync_sync.worker.js" "$POWERSYNC_SYNC_WORKER_MIN_BYTES"
(
  cd "$WASM_BUILD"
  sha256sum -c "$CLIENT_DIR/web/powersync-assets.sha256"
) || fail "Wasm build PowerSync asset checksum mismatch"

default_js_bytes="$(file_size "$DEFAULT_BUILD/main.dart.js")"
app_wasm_bytes="$(file_size "$app_wasm")"
renderer_wasm_bytes="$(file_size "$renderer_wasm")"
default_duration_ms="$((default_finished - default_started))"
wasm_duration_ms="$((wasm_finished - wasm_started))"

if [[ "$REUSE_BUILDS" != "1" ]]; then
  cat > "$REPORT_FILE" <<EOF
{
  "app_version": "$APP_VERSION",
  "default": {
    "build_duration_ms": $default_duration_ms,
    "main_js_bytes": $default_js_bytes
  },
  "wasm": {
    "build_duration_ms": $wasm_duration_ms,
    "application_wasm_bytes": $app_wasm_bytes,
    "application_wasm_path": "${app_wasm#$CLIENT_DIR/}",
    "renderer_wasm_bytes": $renderer_wasm_bytes,
    "renderer_wasm_path": "${renderer_wasm#$CLIENT_DIR/}"
  },
  "runtime_marks": [
    "lifly-host-feedback",
    "lifly-entrypoint-loaded",
    "lifly-engine-initialized",
    "lifly-dart-entrypoint",
    "lifly-flutter-first-frame",
    "lifly-core-usable",
    "lifly-theme-activated"
  ]
}
EOF
fi

echo "[PASS] Web theme performance gate"
echo "Report: $REPORT_FILE"
