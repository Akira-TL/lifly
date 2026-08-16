#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT="${LIFLY_COMPUTE_NODE_BUNDLE_DIR:-$PROJECT_ROOT/build/desktop-compute-node}"
RUNTIME="$OUTPUT/runtime"

command -v node >/dev/null 2>&1 || {
  echo "Node.js is required to build the Compute Node companion" >&2
  exit 2
}
command -v pnpm >/dev/null 2>&1 || {
  echo "pnpm is required to build the Compute Node companion" >&2
  exit 2
}

bash "$SCRIPT_DIR/build-runtime-helpers.sh"
pnpm --dir "$PROJECT_ROOT/services/local-mcp" build

rm -rf "$OUTPUT"
mkdir -p "$RUNTIME/local-mcp/node_modules" "$RUNTIME/provider-api" "$OUTPUT/scripts"

# Local MCP's TypeScript build already contains the compiled protocol and
# local-core workspace sources. zod is its only non-Node runtime dependency.
cp -a "$PROJECT_ROOT/services/local-mcp/dist" "$RUNTIME/local-mcp/dist"
cp "$PROJECT_ROOT/services/local-mcp/package.json" "$RUNTIME/local-mcp/package.json"
ZOD_DIR="$(readlink -f "$PROJECT_ROOT/services/local-mcp/node_modules/zod")"
[[ -d "$ZOD_DIR" ]] || { echo "zod runtime dependency is unavailable" >&2; exit 1; }
cp -a "$ZOD_DIR" "$RUNTIME/local-mcp/node_modules/zod"

cp -a "$PROJECT_ROOT/apps/client_flutter/build/runtime/local-core-bridge" \
  "$RUNTIME/local-core-bridge"
install -m 0755 "$PROJECT_ROOT/build/runtime/lifly-opaque-helper" \
  "$RUNTIME/lifly-opaque-helper"

# Provider execution remains a companion subprocess in v0.9.0. Bundle its
# source/lock contract; uv resolves the already-frozen environment on the host.
cp -a "$PROJECT_ROOT/services/api/app" "$RUNTIME/provider-api/app"
cp "$PROJECT_ROOT/services/api/pyproject.toml" "$RUNTIME/provider-api/pyproject.toml"
cp "$PROJECT_ROOT/services/api/uv.lock" "$RUNTIME/provider-api/uv.lock"

for script in compute-node-start.sh ai-provider-worker.sh compute-node-acceptance.mjs; do
  install -m 0755 "$PROJECT_ROOT/scripts/$script" "$OUTPUT/scripts/$script"
done

cat >"$OUTPUT/run-compute-node.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BUNDLE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LIFLY_OPAQUE_CLIENT_HELPER="${LIFLY_OPAQUE_CLIENT_HELPER:-$BUNDLE_ROOT/runtime/lifly-opaque-helper}"
export LIFLY_LOCAL_CORE_BRIDGE_PATH="${LIFLY_LOCAL_CORE_BRIDGE_PATH:-$BUNDLE_ROOT/runtime/local-core-bridge/client_flutter}"
export LIFLY_LOCAL_MCP_ROOT="${LIFLY_LOCAL_MCP_ROOT:-$BUNDLE_ROOT/runtime/local-mcp}"
export LIFLY_AI_PROVIDER_PROJECT_DIR="${LIFLY_AI_PROVIDER_PROJECT_DIR:-$BUNDLE_ROOT/runtime/provider-api}"
export LIFLY_COMPUTE_NODE_LOG_DIR="${LIFLY_COMPUTE_NODE_LOG_DIR:-$HOME/.local/state/lifly/logs}"
exec node "$BUNDLE_ROOT/scripts/compute-node-acceptance.mjs" "$@"
EOF
chmod 0755 "$OUTPUT/run-compute-node.sh"

node -e "import('${RUNTIME}/local-mcp/dist/services/local-mcp/src/index.js').then(()=>console.log('COMPUTE_NODE_BUNDLE_IMPORT=PASS'))"
"$OUTPUT/run-compute-node.sh" --check-env

printf 'COMPUTE_NODE_BUNDLE=PASS path=%s\n' "$OUTPUT"
