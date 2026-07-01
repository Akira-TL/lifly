#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/apps/client_flutter"

cd "$APP_DIR"

echo "[1/3] flutter pub get"
flutter pub get

echo "[2/3] flutter analyze"
flutter analyze

echo "[3/3] flutter test"
flutter test
