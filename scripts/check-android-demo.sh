#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLIENT_DIR="$ROOT_DIR/apps/client_flutter"
ANDROID_DIR="$CLIENT_DIR/android"
MANIFEST="$ANDROID_DIR/app/src/main/AndroidManifest.xml"
APP_GRADLE="$ANDROID_DIR/app/build.gradle.kts"
ROOT_GRADLE="$ANDROID_DIR/build.gradle.kts"
MAIN_ACTIVITY="$ANDROID_DIR/app/src/main/kotlin/com/lifly/app/MainActivity.kt"
NOTIFICATION_ICON="$ANDROID_DIR/app/src/main/res/drawable/ic_stat_lifly.xml"

fail() {
  printf '[android-demo] FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' '[android-demo] checking Android packaging contract'
grep -q 'applicationId = "com.lifly.app"' "$APP_GRADLE" || fail 'applicationId must be com.lifly.app'
grep -q 'namespace = "com.lifly.app"' "$APP_GRADLE" || fail 'namespace must be com.lifly.app'
grep -q 'compileSdk = 37' "$APP_GRADLE" || fail 'app must compile against Android API 37'
grep -q 'compileSdkMinor = 0' "$APP_GRADLE" || fail 'app must compile against Android API 37.0'
grep -q 'name == "flutter_secure_storage"' "$ROOT_GRADLE" || fail 'flutter_secure_storage API 37.0 compatibility override is missing'
grep -q 'android.permission.INTERNET' "$MANIFEST" || fail 'main manifest must declare INTERNET'
grep -q 'android.permission.POST_NOTIFICATIONS' "$MANIFEST" || fail 'main manifest must declare POST_NOTIFICATIONS'
grep -q 'android:label="Lifly"' "$MANIFEST" || fail 'app label must be Lifly'
grep -q '^package com.lifly.app$' "$MAIN_ACTIVITY" || fail 'MainActivity package must match application namespace'
[[ -f "$NOTIFICATION_ICON" ]] || fail 'notification small icon must exist as a drawable resource'
grep -q "AndroidInitializationSettings('ic_stat_lifly')" \
  "$CLIENT_DIR/lib/features/reminders/data/android_reminder_notification_adapter.dart" \
  || fail 'Android notification adapter must use the drawable small icon'
if grep -q 'signingConfigs.getByName("debug")' "$APP_GRADLE"; then
  fail 'release build must not use the debug signing key'
fi
if git -C "$ROOT_DIR" ls-files --error-unmatch apps/client_flutter/android/key.properties >/dev/null 2>&1; then
  fail 'android/key.properties must never be tracked'
fi
git -C "$ROOT_DIR" check-ignore -q apps/client_flutter/android/key.properties || fail 'android/key.properties must stay gitignored'

cd "$CLIENT_DIR"

printf '%s\n' '[android-demo] checking reminder formatting'
dart format --output=none --set-exit-if-changed \
  lib/features/reminders \
  test/reminder_*.dart

printf '%s\n' '[android-demo] analyzing reminder code'
flutter analyze --no-pub \
  lib/features/reminders \
  test/reminder_*.dart

printf '%s\n' '[android-demo] running reminder tests'
flutter test --no-pub test/reminder_*.dart

printf '%s\n' '[android-demo] building Android debug APK'
flutter build apk --debug --no-pub
