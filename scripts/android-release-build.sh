#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"
ANDROID_DIR="$CLIENT_DIR/android"
KEY_PROPERTIES="$ANDROID_DIR/key.properties"
APK="$CLIENT_DIR/build/app/outputs/flutter-apk/app-release.apk"

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  cat >&2 <<'EOF'
Android release signing is not configured.
Create apps/client_flutter/android/key.properties with storeFile/storePassword/keyAlias/keyPassword.
The keystore and key.properties are gitignored and must never be committed.
EOF
  exit 2
fi

for key in storeFile storePassword keyAlias keyPassword; do
  grep -Eq "^${key}=.+" "$KEY_PROPERTIES" || {
    echo "Missing Android release signing property: $key" >&2
    exit 2
  }
done

bash "$SCRIPT_DIR/build-native-opaque.sh" android
(
  cd "$CLIENT_DIR"
  flutter clean
  flutter pub get
  flutter build apk --release \
    --target-platform android-arm,android-arm64,android-x64
)

[[ -f "$APK" ]] || { echo "Android release APK missing: $APK" >&2; exit 1; }

sdk_dir="${ANDROID_SDK_ROOT:-}"
if [[ -z "$sdk_dir" && -f "$ANDROID_DIR/local.properties" ]]; then
  sdk_dir="$(sed -n 's/^sdk\.dir=//p' "$ANDROID_DIR/local.properties" | tail -1)"
fi
apksigner=""
if [[ -n "$sdk_dir" && -d "$sdk_dir/build-tools" ]]; then
  apksigner="$(find "$sdk_dir/build-tools" -mindepth 2 -maxdepth 2 -type f -name apksigner -print | sort -V | tail -1)"
fi
if [[ -z "$apksigner" ]]; then
  echo "Android apksigner not found; cannot accept a release artifact without signature verification" >&2
  exit 2
fi
"$apksigner" verify --verbose "$APK" >/dev/null

printf 'ANDROID_RELEASE=PASS apk=%s signed=true opaque_native=true\n' "$APK"
