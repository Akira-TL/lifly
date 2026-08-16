#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$PROJECT_ROOT/tools/opaque-helper/Cargo.toml"
OUTPUT_ROOT="$PROJECT_ROOT/build/native-opaque"
PLATFORM="${1:-}"

if [[ -z "$PLATFORM" ]]; then
  echo "Usage: $0 linux|android|windows" >&2
  exit 2
fi

cargo_bin="${LIFLY_CARGO_BIN:-$(command -v cargo || true)}"
rustup_bin="${LIFLY_RUSTUP_BIN:-$(command -v rustup || true)}"
if [[ -z "$cargo_bin" ]]; then
  echo "Cargo is required to build the native OPAQUE runtime" >&2
  exit 2
fi

build_linux() {
  "$cargo_bin" build --release --manifest-path "$MANIFEST"
  local source="$PROJECT_ROOT/tools/opaque-helper/target/release/liblifly_opaque_helper.so"
  [[ -f "$source" ]] || { echo "Missing Linux OPAQUE cdylib: $source" >&2; exit 1; }
  mkdir -p "$OUTPUT_ROOT/linux"
  install -m 0755 "$source" "$OUTPUT_ROOT/linux/liblifly_opaque_helper.so"
  echo "OPAQUE_NATIVE_LINUX=$OUTPUT_ROOT/linux/liblifly_opaque_helper.so"
}

ensure_rust_target() {
  local target="$1"
  if [[ -n "$rustup_bin" ]] && "$rustup_bin" target list --installed | grep -Fxq "$target"; then
    return
  fi
  [[ -n "$rustup_bin" ]] || {
    echo "Rust target $target is missing and rustup is unavailable" >&2
    exit 2
  }
  "$rustup_bin" target add "$target"
}

android_sdk_dir() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi
  local properties="$PROJECT_ROOT/apps/client_flutter/android/local.properties"
  if [[ -f "$properties" ]]; then
    local configured
    configured="$(sed -n 's/^sdk\.dir=//p' "$properties" | tail -1)"
    if [[ -n "$configured" ]]; then
      printf '%s\n' "$configured"
      return
    fi
  fi
  printf '%s\n' "$HOME/Android/Sdk"
}

build_android() {
  local sdk ndk_version ndk toolchain api
  sdk="$(android_sdk_dir)"
  ndk_version="${LIFLY_ANDROID_NDK_VERSION:-28.2.13676358}"
  ndk="$sdk/ndk/$ndk_version"
  toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
  api="${LIFLY_ANDROID_MIN_SDK:-24}"
  [[ -d "$toolchain" ]] || {
    echo "Android NDK toolchain not found: $toolchain" >&2
    exit 2
  }

  local target abi linker env_name source
  while IFS='|' read -r target abi linker env_name; do
    ensure_rust_target "$target"
    source="$PROJECT_ROOT/tools/opaque-helper/target/$target/release/liblifly_opaque_helper.so"
    env \
      "CARGO_TARGET_${env_name}_LINKER=$toolchain/${linker}${api}-clang" \
      "$cargo_bin" build --release --manifest-path "$MANIFEST" --target "$target"
    [[ -f "$source" ]] || { echo "Missing Android OPAQUE cdylib: $source" >&2; exit 1; }
    mkdir -p "$OUTPUT_ROOT/android/$abi"
    install -m 0755 "$source" "$OUTPUT_ROOT/android/$abi/liblifly_opaque_helper.so"
  done <<'TARGETS'
aarch64-linux-android|arm64-v8a|aarch64-linux-android|AARCH64_LINUX_ANDROID
armv7-linux-androideabi|armeabi-v7a|armv7a-linux-androideabi|ARMV7_LINUX_ANDROIDEABI
x86_64-linux-android|x86_64|x86_64-linux-android|X86_64_LINUX_ANDROID
TARGETS

  echo "OPAQUE_NATIVE_ANDROID=$OUTPUT_ROOT/android"
}

build_windows() {
  if [[ "${OS:-}" != "Windows_NT" ]]; then
    echo "Windows OPAQUE runtime must be built on a Windows host; cross-build is not accepted by the Demo gate" >&2
    exit 3
  fi
  "$cargo_bin" build --release --manifest-path "$MANIFEST"
  local source="$PROJECT_ROOT/tools/opaque-helper/target/release/lifly_opaque_helper.dll"
  [[ -f "$source" ]] || { echo "Missing Windows OPAQUE DLL: $source" >&2; exit 1; }
  mkdir -p "$OUTPUT_ROOT/windows"
  install -m 0755 "$source" "$OUTPUT_ROOT/windows/lifly_opaque_helper.dll"
  echo "OPAQUE_NATIVE_WINDOWS=$OUTPUT_ROOT/windows/lifly_opaque_helper.dll"
}

case "$PLATFORM" in
  linux) build_linux ;;
  android) build_android ;;
  windows) build_windows ;;
  *) echo "Unsupported native OPAQUE platform: $PLATFORM" >&2; exit 2 ;;
esac
