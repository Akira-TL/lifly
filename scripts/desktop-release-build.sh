#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"
FLUTTER_BUNDLE="$CLIENT_DIR/build/linux/x64/release/bundle"
BUNDLE="$PROJECT_ROOT/build/desktop-client"
OPAQUE_LIB="$BUNDLE/lib/liblifly_opaque_helper.so"

mkdir -p "$PROJECT_ROOT/build"
exec 9>"$PROJECT_ROOT/build/.flutter-linux-build.lock"
if command -v flock >/dev/null 2>&1; then
  flock 9
fi

bash "$SCRIPT_DIR/build-native-opaque.sh" linux
(
  cd "$CLIENT_DIR"
  flutter pub get
  # Avoid stale CMake install prefixes and cross-target helper state.
  rm -rf build/linux
  flutter build linux --release
)

[[ -x "$FLUTTER_BUNDLE/client_flutter" ]] || {
  echo "Desktop release binary missing: $FLUTTER_BUNDLE/client_flutter" >&2
  exit 1
}
rm -rf "$BUNDLE"
cp -a "$FLUTTER_BUNDLE" "$BUNDLE"
[[ -f "$OPAQUE_LIB" ]] || {
  echo "Desktop release is not self-contained: bundled OPAQUE library missing" >&2
  exit 1
}

printf 'DESKTOP_RELEASE=PASS bundle=%s opaque_native=%s\n' "$BUNDLE" "$OPAQUE_LIB"
