#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"
PUBLIC_WEB_DIR="$PROJECT_ROOT/build/public-web"

cd "$PROJECT_ROOT"
echo "=== Lifly v0.9.0 Demo Delivery Gate ==="

echo "[1/6] Web release"
bash scripts/web-release-build.sh
test -s "$PUBLIC_WEB_DIR/sqlite3mc.wasm"
test -s "$PUBLIC_WEB_DIR/opaque_client.js"

echo "[2/6] Native OPAQUE"
bash scripts/opaque-native-smoke.sh

echo "[3/6] Linux Desktop release"
if [[ "$(uname -s)" == "Linux" ]]; then
  bash scripts/desktop-release-build.sh
else
  echo "LINUX_DESKTOP_RELEASE=SKIPPED_HOST"
fi

echo "[4/6] Android installable demo"
if [[ "$(uname -s)" == "Linux" ]]; then
  bash scripts/check-android-demo.sh
  if [[ -f "$CLIENT_DIR/android/key.properties" ]]; then
    bash scripts/android-release-build.sh
  else
    echo "ANDROID_RELEASE=BLOCKED_BY_SIGNING key_properties=missing"
  fi
else
  echo "ANDROID_DEMO=SKIPPED_HOST"
fi

echo "[5/6] Compute Node companion / Desktop demo bundle"
if [[ "$(uname -s)" == "Linux" ]]; then
  bash scripts/build-compute-node-companion.sh
  bash scripts/assemble-desktop-demo-bundle.sh
else
  echo "COMPUTE_NODE_COMPANION=UNVERIFIED_HOST"
fi

echo "[6/6] Windows release status"
if [[ "${OS:-}" == "Windows_NT" ]]; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/windows-release-build.ps1
else
  echo "WINDOWS_RELEASE=UNVERIFIED_HOST requires=real_windows"
fi

echo "DELIVERY_GATE=PASS_WITH_EXTERNAL_BLOCKERS"
echo "GOLDEN_LIVE=NOT_RUN"
