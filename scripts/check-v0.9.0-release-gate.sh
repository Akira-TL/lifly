#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

cd "$PROJECT_ROOT"

echo "=== Lifly v0.9.0 integration release gate ==="

echo "[1/7] Static product/security invariants"
grep -Fq "defaultValue: '0.9.0'" apps/client_flutter/lib/app/app_config.dart
grep -Eq '^version: 0\.9\.0\+' apps/client_flutter/pubspec.yaml
grep -Fq 'version="0.9.0"' services/api/app/main.py
grep -Fq 'version = "0.9.0"' services/api/pyproject.toml

grep -Fq 'accessTokenProvider: sessions.readAccessToken' apps/client_flutter/lib/main.dart
grep -Fq 'PlaintextE2eeMigrator(' apps/client_flutter/lib/data/crypto/account_e2ee_runtime.dart
grep -Fq 'auditPayloadProtector: e2eeRuntime' apps/client_flutter/lib/main.dart
grep -Fq 'Depends(get_active_subject)' services/api/app/modules/ai/router.py

if rg -n 'DEFAULT_LOCAL_USER_ID|local-dev' \
  services/api/app/modules --glob '*router.py' --glob 'cloud_server.py'; then
  echo "FAIL: public router still contains local/dev identity" >&2
  exit 1
fi


echo "[2/7] Runtime topology and scripts"
bash -n \
  scripts/dev-start.sh \
  scripts/dev-stop.sh \
  scripts/dev-restart.sh \
  scripts/compute-node-start.sh \
  scripts/ai-provider-worker.sh \
  scripts/build-runtime-helpers.sh \
  scripts/local-core-bridge.sh \
  scripts/e2ee-commit-smoke.sh \
  scripts/run-v0.9.0-golden.sh \
  scripts/lib/lifly-ports.sh

compose_render="$(mktemp)"
trap 'rm -f "$compose_render"' EXIT
LIFLY_COMMON_POSTGRES_PORT="$LIFLY_COMMON_POSTGRES_PORT" \
LIFLY_COMMON_REDIS_PORT="$LIFLY_COMMON_REDIS_PORT" \
LIFLY_COMMON_MINIO_API_PORT="$LIFLY_COMMON_MINIO_API_PORT" \
LIFLY_COMMON_MINIO_CONSOLE_PORT="$LIFLY_COMMON_MINIO_CONSOLE_PORT" \
LIFLY_COMMON_POWERSYNC_PORT="$LIFLY_COMMON_POWERSYNC_PORT" \
LIFLY_COMMON_OLLAMA_PORT="$LIFLY_COMMON_OLLAMA_PORT" \
  docker compose --profile powersync --profile ai -f infra/docker-compose.yml config >"$compose_render"
if grep -Eq 'host_ip: (0\.0\.0\.0|::)' "$compose_render"; then
  echo "FAIL: infrastructure port exposed beyond loopback" >&2
  exit 1
fi
for port in \
  "$LIFLY_COMMON_POSTGRES_PORT" \
  "$LIFLY_COMMON_REDIS_PORT" \
  "$LIFLY_COMMON_MINIO_API_PORT" \
  "$LIFLY_COMMON_MINIO_CONSOLE_PORT" \
  "$LIFLY_COMMON_POWERSYNC_PORT" \
  "$LIFLY_COMMON_OLLAMA_PORT"; do
  grep -Fq "published: \"$port\"" "$compose_render"
done

echo "[3/7] OPAQUE / Python P0 integration contracts"
cargo_bin="${LIFLY_CARGO_BIN:-}"
if [[ -z "$cargo_bin" && -x "$HOME/.cargo/bin/cargo" ]]; then
  cargo_bin="$HOME/.cargo/bin/cargo"
fi
if [[ -z "$cargo_bin" ]]; then
  cargo_bin="$(command -v cargo || true)"
fi
if [[ -z "$cargo_bin" ]]; then
  echo "FAIL: Cargo is required to verify the OPAQUE runtime helper" >&2
  exit 1
fi
"$cargo_bin" test --manifest-path tools/opaque-helper/Cargo.toml

(
  cd services/api
  uv run pytest -q \
    tests/test_ai_relay_api.py \
    tests/test_ai_provider_contract.py \
    tests/test_cloud_ai_privacy.py \
    tests/test_local_ai_provider_worker.py \
    tests/test_mcp_auth_contract.py \
    tests/test_mcp_capture_commit_service.py \
    tests/test_mcp_capture_lifecycle_contract.py \
    tests/test_mcp_capture_session_contract.py \
    tests/test_mcp_capture_undo_contract.py \
    tests/test_mcp_cloud_local_parity_contract.py \
    tests/test_import_commit_contract.py \
    tests/test_import_rollback_contract.py \
    tests/test_export_contract.py \
    tests/test_sync_credentials.py \
    tests/test_sync_push_service.py
)

echo "[4/7] Shared protocol / Local Core / Local MCP"
pnpm --dir packages/protocol typecheck
pnpm --dir packages/protocol test
pnpm --dir packages/local-core typecheck
pnpm --dir packages/local-core test
pnpm --dir services/local-mcp typecheck
env -u LIFLY_LOCAL_CORE_BRIDGE_PATH pnpm --dir services/local-mcp test

echo "[5/7] Flutter P0 integration contracts"
(
  cd apps/client_flutter
  dart analyze \
    lib/main.dart \
    lib/data/api/api_client.dart \
    lib/data/auth/pake_client_adapter.dart \
    lib/data/crypto/account_e2ee_runtime.dart \
    lib/data/ai/device_ai_job_cipher.dart \
    lib/data/local_core/powersync_local_core_bridge.dart \
    lib/data/local_core/desktop_local_core_host.dart \
    lib/features/ai_capture/data/compute_node_plan_client.dart \
    lib/features/ai_capture/data/ai_capture_execution_runtime.dart \
    lib/features/ai_capture/data/external_ai_action_committer.dart \
    lib/features/asset/data/asset_e2ee_sync_adapter.dart
  flutter test \
    test/api_client_auth_session_test.dart \
    test/auth_repository_test.dart \
    test/auth_session_store_test.dart \
    test/pake_client_helper_adapter_test.dart \
    test/compute_node_plan_client_test.dart \
    test/ai_capture_execution_runtime_test.dart \
    test/account_e2ee_runtime_test.dart \
    test/asset_audit_e2ee_test.dart \
    test/asset_repository_test.dart \
    test/powersync_encrypted_sync_store_test.dart \
    test/powersync_password_key_envelope_service_test.dart \
    test/local_core_write_test.dart \
    test/powersync_local_core_bridge_test.dart \
    test/desktop_local_core_host_test.dart \
    test/external_ai_action_committer_test.dart
)

echo "[6/7] Golden runtime prerequisites / live run"
default_opaque="$PROJECT_ROOT/build/runtime/lifly-opaque-helper"
default_bridge="$PROJECT_ROOT/scripts/local-core-bridge.sh"
resolved_server_helper="${LIFLY_OPAQUE_SERVER_HELPER:-$default_opaque}"
resolved_client_helper="${LIFLY_OPAQUE_CLIENT_HELPER:-$resolved_server_helper}"
resolved_bridge="${LIFLY_LOCAL_CORE_BRIDGE_PATH:-$default_bridge}"

if [[ "${LIFLY_RUN_GOLDEN_RUNTIME:-false}" == "true" ]]; then
  LIFLY_OPAQUE_SERVER_HELPER="$resolved_server_helper" \
  LIFLY_OPAQUE_CLIENT_HELPER="$resolved_client_helper" \
  LIFLY_LOCAL_CORE_BRIDGE_PATH="$resolved_bridge" \
    bash scripts/run-v0.9.0-golden.sh
else
  missing=()
  command -v docker >/dev/null 2>&1 || missing+=("docker")
  command -v ollama >/dev/null 2>&1 || missing+=("ollama")
  [[ -x "$resolved_server_helper" ]] || missing+=("LIFLY_OPAQUE_SERVER_HELPER")
  [[ -x "$resolved_client_helper" ]] || missing+=("LIFLY_OPAQUE_CLIENT_HELPER")
  [[ -x "$resolved_bridge" ]] || missing+=("LIFLY_LOCAL_CORE_BRIDGE_PATH")
  installed_model=""
  if command -v ollama >/dev/null 2>&1; then
    installed_model="$(ollama list 2>/dev/null | awk 'NR==2 {print $1}')"
  fi
  if [[ -z "${LIFLY_LOCAL_AI_MODEL:-}" && -z "$installed_model" ]]; then
    missing+=("LIFLY_LOCAL_AI_MODEL/or installed Ollama model")
  fi
  if ((${#missing[@]} > 0)); then
    printf 'GOLDEN_RUNTIME=BLOCKED_BY_ENV missing=%s\n' "$(IFS=,; echo "${missing[*]}")"
  else
    echo "GOLDEN_RUNTIME=READY"
  fi
fi

echo "[7/7] Gate result"
echo "CONTRACT_GATE=PASS"
