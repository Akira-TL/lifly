#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"
PUBLIC_WEB_DIR="$PROJECT_ROOT/build/public-web"

export LIFLY_DEPLOY_SLOT="${LIFLY_DEPLOY_SLOT:-dev}"
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

DATA_MODE="${LIFLY_DATA_MODE:-api}"
API_BASE_URL="${LIFLY_API_BASE_URL:-https://lifly.babelbeast.com/api/v1}"
APP_VERSION="${LIFLY_APP_VERSION:-0.9.0}"

printf '%s\n' "构建 Lifly Flutter Web release"
printf '%s\n' "  DataMode: $DATA_MODE"
printf '%s\n' "  API:      $API_BASE_URL"
printf '%s\n' "  Version:  $APP_VERSION"
printf '%s\n' "  OPAQUE:   same-origin WebAssembly"

bash "$SCRIPT_DIR/build-opaque-web-client.sh"

cd "$CLIENT_DIR"
flutter build web --release \
  --pwa-strategy=none \
  --dart-define="LIFLY_DATA_MODE=$DATA_MODE" \
  --dart-define="LIFLY_API_BASE_URL=$API_BASE_URL" \
  --dart-define="LIFLY_APP_VERSION=$APP_VERSION" \
  --dart-define="LIFLY_VISUAL_FIXTURES=false"


staging_dir="$PROJECT_ROOT/build/.public-web.$$.tmp"
rm -rf "$staging_dir"
mkdir -p "$staging_dir"
cp -a "$CLIENT_DIR/build/web/." "$staging_dir/"

# Flutter clean/build only owns apps/client_flutter/build. Keep the public web
# bundle outside that tree so Android/Desktop builds cannot take production Web
# offline by deleting Flutter's transient build directory.
rm -rf "$PUBLIC_WEB_DIR.previous"
if [[ -d "$PUBLIC_WEB_DIR" ]]; then
  mv "$PUBLIC_WEB_DIR" "$PUBLIC_WEB_DIR.previous"
fi
mv "$staging_dir" "$PUBLIC_WEB_DIR"
rm -rf "$PUBLIC_WEB_DIR.previous"

echo "Flutter Web build: $CLIENT_DIR/build/web"
echo "Public Web release: $PUBLIC_WEB_DIR"
