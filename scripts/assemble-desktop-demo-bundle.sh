#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLIENT_SOURCE="$PROJECT_ROOT/build/desktop-client"
COMPUTE_SOURCE="$PROJECT_ROOT/build/desktop-compute-node"
OUTPUT="${LIFLY_DESKTOP_DEMO_BUNDLE_DIR:-$PROJECT_ROOT/build/lifly-desktop-demo}"

[[ -x "$CLIENT_SOURCE/client_flutter" ]] || {
  echo "Desktop Client release is missing; run scripts/desktop-release-build.sh" >&2
  exit 2
}
[[ -x "$COMPUTE_SOURCE/run-compute-node.sh" ]] || {
  echo "Compute Node companion is missing; run scripts/build-compute-node-companion.sh" >&2
  exit 2
}

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
cp -a "$CLIENT_SOURCE" "$OUTPUT/client"
cp -a "$COMPUTE_SOURCE" "$OUTPUT/compute-node"

cat >"$OUTPUT/run-lifly-demo.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$BUNDLE_ROOT/client/client_flutter" &
CLIENT_PID=$!
cleanup() {
  kill "$CLIENT_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
exec "$BUNDLE_ROOT/compute-node/run-compute-node.sh" "$@"
EOF
chmod 0755 "$OUTPUT/run-lifly-demo.sh"

printf 'DESKTOP_DEMO_BUNDLE=PASS path=%s client=true compute_node=true\n' "$OUTPUT"
