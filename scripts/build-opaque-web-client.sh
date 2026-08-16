#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER_DIR="$PROJECT_ROOT/tools/opaque-helper"
WEB_DIR="$PROJECT_ROOT/apps/client_flutter/web"
TARGET_WASM="$HELPER_DIR/target/wasm32-unknown-unknown/release/lifly_opaque_helper.wasm"

command -v cargo >/dev/null 2>&1 || { echo '缺少 cargo' >&2; exit 1; }
command -v rustup >/dev/null 2>&1 || { echo '缺少 rustup' >&2; exit 1; }
command -v wasm-bindgen >/dev/null 2>&1 || { echo '缺少 wasm-bindgen-cli' >&2; exit 1; }

if ! rustup target list --installed | grep -Fxq wasm32-unknown-unknown; then
  rustup target add wasm32-unknown-unknown
fi

(
  cd "$HELPER_DIR"
  cargo build --release --target wasm32-unknown-unknown
)

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
wasm-bindgen \
  --target web \
  --out-dir "$TMP_DIR" \
  --out-name opaque_client \
  "$TARGET_WASM"

install -m 0644 "$TMP_DIR/opaque_client.js" "$WEB_DIR/opaque_client.js"
install -m 0644 "$TMP_DIR/opaque_client_bg.wasm" "$WEB_DIR/opaque_client_bg.wasm"

echo "OPAQUE WebAssembly client 已构建到 $WEB_DIR"
