#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_DIR="$PROJECT_ROOT/apps/client_flutter"

cargo_bin="${LIFLY_CARGO_BIN:-}"
if [[ -z "$cargo_bin" ]]; then
  if [[ -x "$HOME/.cargo/bin/cargo" ]]; then
    cargo_bin="$HOME/.cargo/bin/cargo"
  else
    cargo_bin="$(command -v cargo || true)"
  fi
fi
if [[ -z "$cargo_bin" ]]; then
  echo "缺少 Cargo；OPAQUE helper 需要 Rust 1.87+" >&2
  exit 2
fi

mkdir -p "$PROJECT_ROOT/build/runtime" "$CLIENT_DIR/build/runtime"
LOCK_FILE="$PROJECT_ROOT/build/.flutter-linux-build.lock"
exec 9>"$LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  flock 9
fi

echo "[runtime] testing RFC 9807 OPAQUE helper"
"$cargo_bin" test --manifest-path "$PROJECT_ROOT/tools/opaque-helper/Cargo.toml"
echo "[runtime] building RFC 9807 OPAQUE helper"
"$cargo_bin" build --release --manifest-path "$PROJECT_ROOT/tools/opaque-helper/Cargo.toml"
install -m 0755 \
  "$PROJECT_ROOT/tools/opaque-helper/target/release/lifly-opaque-helper" \
  "$PROJECT_ROOT/build/runtime/lifly-opaque-helper"

build_flutter_bundle() {
  local target="$1"
  local output_name="$2"
  local build_log="$PROJECT_ROOT/logs/runtime-${output_name}-build.log"
  local stage="$CLIENT_DIR/build/runtime/${output_name}-stage"
  local output="$CLIENT_DIR/build/runtime/$output_name"
  local rc=0

  mkdir -p "$PROJECT_ROOT/logs"
  echo "[runtime] building Flutter target $target"
  (
    cd "$CLIENT_DIR"
    # Flutter reuses one CMake tree for all Linux targets. Remove it before each
    # helper target so an earlier main-app/helper install prefix cannot leak into
    # this bundle. The shared flock above prevents concurrent Desktop builds.
    rm -rf build/linux
    set +e
    flutter build linux --release --target "$target" >"$build_log" 2>&1
    rc=$?
    set -e
    if [[ $rc -ne 0 ]] && ! grep -Fq 'to "/usr/local/client_flutter": Permission denied' "$build_log"; then
      cat "$build_log" >&2
      exit "$rc"
    fi

    if [[ ! -f build/linux/x64/release/intermediates_do_not_run/client_flutter ]]; then
      cat "$build_log" >&2
      echo "Flutter Linux target did not produce an executable" >&2
      exit 1
    fi

    rm -rf "$stage" "$output"
    mkdir -p "$stage"
    DESTDIR="$stage" cmake --install build/linux/x64/release >/dev/null
    staged_binary="$(find "$stage" -type f -name client_flutter -perm -u+x -print -quit)"
    if [[ -z "$staged_binary" ]]; then
      echo "Flutter Linux staged bundle is incomplete: $target" >&2
      exit 1
    fi
    staged_bundle="$(dirname "$staged_binary")"
    mv "$staged_bundle" "$output"
    rm -rf "$stage"
  )
}

build_flutter_bundle lib/local_core_host_main.dart local-core-bridge
build_flutter_bundle lib/e2ee_commit_smoke_main.dart e2ee-commit-smoke
build_flutter_bundle lib/sqlcipher_smoke_main.dart sqlcipher-smoke
build_flutter_bundle lib/encrypted_write_smoke_main.dart encrypted-write-smoke

echo "OPAQUE_HELPER=$PROJECT_ROOT/build/runtime/lifly-opaque-helper"
echo "LOCAL_CORE_BRIDGE=$PROJECT_ROOT/scripts/local-core-bridge.sh"
echo "E2EE_COMMIT_SMOKE=$PROJECT_ROOT/scripts/e2ee-commit-smoke.sh"
echo "SQLCIPHER_SMOKE=$PROJECT_ROOT/scripts/sqlcipher-smoke.sh"
echo "ENCRYPTED_WRITE_SMOKE=$PROJECT_ROOT/scripts/encrypted-write-smoke.sh"
