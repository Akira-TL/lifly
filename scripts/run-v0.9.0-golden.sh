#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/lifly-ports.sh
source "$SCRIPT_DIR/lib/lifly-ports.sh"

GOLDEN_API_PORT="${LIFLY_GOLDEN_API_PORT:-8239}"
OPAQUE_HELPER="${LIFLY_OPAQUE_SERVER_HELPER:-$PROJECT_ROOT/build/runtime/lifly-opaque-helper}"
CLIENT_HELPER="${LIFLY_OPAQUE_CLIENT_HELPER:-$OPAQUE_HELPER}"
LOCAL_CORE_BRIDGE="${LIFLY_LOCAL_CORE_BRIDGE_PATH:-$PROJECT_ROOT/scripts/local-core-bridge.sh}"
E2EE_COMMIT_SMOKE="${LIFLY_E2EE_COMMIT_SMOKE_PATH:-$PROJECT_ROOT/scripts/e2ee-commit-smoke.sh}"
LOCAL_AI_ENDPOINT="${LIFLY_LOCAL_AI_ENDPOINT:-http://127.0.0.1:11434}"
LOCAL_AI_MODEL="${LIFLY_LOCAL_AI_MODEL:-qwen3.5:4b}"
GOLDEN_ID="${LIFLY_GOLDEN_ID:-$$}"
GOLDEN_DB="lifly_golden_${GOLDEN_ID//[^a-zA-Z0-9_]/_}"
OPAQUE_SETUP="${LIFLY_OPAQUE_SERVER_SETUP_PATH:-/tmp/lifly-opaque-golden-$GOLDEN_ID.bin}"
API_LOG="$PROJECT_ROOT/logs/golden-api-$GOLDEN_ID.log"
E2EE_BOOTSTRAP="/tmp/lifly-golden-e2ee-$GOLDEN_ID.json"
PHONE_DB="/tmp/lifly-golden-phone-$GOLDEN_ID.db"
API_PID=""
DB_CREATED=false

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ -n "$API_PID" ]]; then
    kill -- "-$API_PID" 2>/dev/null || kill "$API_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$API_PID" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 -- "-$API_PID" 2>/dev/null || kill -9 "$API_PID" 2>/dev/null || true
  fi
  if [[ "$DB_CREATED" == true ]]; then
    docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec -T postgres \
      dropdb -U lifly --force --if-exists "$GOLDEN_DB" >/dev/null 2>&1 || true
  fi
  rm -f "$OPAQUE_SETUP" "${OPAQUE_SETUP%.*}.tmp" "$OPAQUE_SETUP.tmp" "$E2EE_BOOTSTRAP" "$PHONE_DB" "$PHONE_DB-shm" "$PHONE_DB-wal"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

mkdir -p "$PROJECT_ROOT/logs"

if [[ ! -x "$OPAQUE_HELPER" || ! -x "$LOCAL_CORE_BRIDGE" || ! -x "$E2EE_COMMIT_SMOKE" ]]; then
  bash "$SCRIPT_DIR/build-runtime-helpers.sh"
fi
for path in "$OPAQUE_HELPER" "$CLIENT_HELPER" "$LOCAL_CORE_BRIDGE" "$E2EE_COMMIT_SMOKE"; do
  if [[ ! -x "$path" ]]; then
    echo "Golden runtime executable unavailable: $path" >&2
    exit 2
  fi
done

if ! curl -fsS --max-time 2 "$LOCAL_AI_ENDPOINT/api/tags" >/dev/null; then
  echo "Host Ollama unavailable: $LOCAL_AI_ENDPOINT" >&2
  exit 2
fi
if ! curl -fsS --max-time 5 "$LOCAL_AI_ENDPOINT/api/tags" \
  | grep -Fq '"name":"'"$LOCAL_AI_MODEL"; then
  echo "Ollama model unavailable: $LOCAL_AI_MODEL" >&2
  exit 2
fi

if ss -ltn | grep -q ":$GOLDEN_API_PORT "; then
  echo "Golden API port already occupied: $GOLDEN_API_PORT" >&2
  exit 2
fi

echo "[golden 1/6] ensure shared PostgreSQL"
docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" up -d postgres >/dev/null

docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec -T postgres \
  createdb -U lifly "$GOLDEN_DB"
DB_CREATED=true

echo "[golden 2/6] verify Desktop Local MCP E2EE executable"
bridge_db="/tmp/lifly-golden-local-core-$GOLDEN_ID.db"
bridge_adk="$(python3 -c 'import base64; print(base64.b64encode(bytes([7]) * 32).decode())')"
bridge_output="$(printf '%s\n%s\n%s\n' \
  "{\"id\":0,\"method\":\"_runtime_init\",\"input\":{\"account_id\":\"golden-local-mcp\",\"key_version\":1,\"account_data_key_base64\":\"$bridge_adk\"}}" \
  '{"id":1,"method":"health","input":null}' \
  '{"id":2,"method":"memo_create","input":{"type":"memo","title":"desktop-local-mcp-golden","content_markdown":"desktop local mcp encrypted write","tags":[]},"context":{"actorType":"ai","sourceChannel":"local_mcp","toolName":"memo_create"}}' \
  | LIFLY_LOCAL_CORE_DB_PATH="$bridge_db" "$LOCAL_CORE_BRIDGE")"
printf '%s\n' "$bridge_output" | grep -Fq '"id":1,"ok":true'
printf '%s\n' "$bridge_output" | grep -Fq '"mode":"powersync"'
printf '%s\n' "$bridge_output" | grep -Fq '"id":2,"ok":true'
python3 - "$bridge_db" <<'PYSQL'
import sqlite3, sys
path = sys.argv[1]
db = sqlite3.connect(path)
try:
    encrypted = db.execute("select count(*) from encrypted_entities").fetchone()[0]
    audit = db.execute("select before_snapshot, after_snapshot, source_text from audit_logs order by created_at desc limit 1").fetchone()
    if encrypted < 2:
        raise SystemExit(f"expected encrypted memo+audit envelopes, got {encrypted}")
    if audit is None or any(value is not None for value in audit):
        raise SystemExit("desktop Local MCP audit leaked plaintext")
finally:
    db.close()
PYSQL
rm -f "$bridge_db" "$bridge_db-shm" "$bridge_db-wal"
echo "GOLDEN_DESKTOP_LOCAL_MCP_E2EE=PASS"

echo "[golden 3/6] start isolated authenticated API"
(
  cd "$PROJECT_ROOT/services/api"
  exec setsid env \
    API_PORT="$GOLDEN_API_PORT" \
    DATABASE_URL="postgresql+asyncpg://lifly:lifly@127.0.0.1:$LIFLY_COMMON_POSTGRES_PORT/$GOLDEN_DB" \
    REDIS_URL="redis://127.0.0.1:$LIFLY_COMMON_REDIS_PORT/0" \
    MINIO_ENDPOINT="http://127.0.0.1:$LIFLY_COMMON_MINIO_API_PORT" \
    POWERSYNC_URL="http://127.0.0.1:$LIFLY_COMMON_POWERSYNC_PORT" \
    LIFLY_OPAQUE_SERVER_HELPER="$OPAQUE_HELPER" \
    LIFLY_OPAQUE_SERVER_SETUP_PATH="$OPAQUE_SETUP" \
    uv run uvicorn app.main:app --host 127.0.0.1 --port "$GOLDEN_API_PORT"
) >"$API_LOG" 2>&1 &
API_PID=$!

for _ in $(seq 1 80); do
  if curl -fsS --max-time 1 "http://127.0.0.1:$GOLDEN_API_PORT/api/v1/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$API_PID" 2>/dev/null; then
    echo "Golden API exited early:" >&2
    tail -n 120 "$API_LOG" >&2 || true
    exit 1
  fi
  sleep 0.25
done
curl -fsS --max-time 2 "http://127.0.0.1:$GOLDEN_API_PORT/api/v1/health" >/dev/null

echo "[golden 4/6] real OPAQUE + encrypted Compute Node + host Ollama"
(
  cd "$PROJECT_ROOT/apps/client_flutter"
  env \
    LIFLY_RUN_GOLDEN_RUNTIME=true \
    LIFLY_GOLDEN_API_BASE_URL="http://127.0.0.1:$GOLDEN_API_PORT/api/v1" \
    LIFLY_GOLDEN_PROJECT_ROOT="$PROJECT_ROOT" \
    LIFLY_OPAQUE_CLIENT_HELPER="$CLIENT_HELPER" \
    LIFLY_LOCAL_CORE_BRIDGE_PATH="$LOCAL_CORE_BRIDGE" \
    LIFLY_LOCAL_AI_ENDPOINT="$LOCAL_AI_ENDPOINT" \
    LIFLY_LOCAL_AI_MODEL="$LOCAL_AI_MODEL" \
    LIFLY_GOLDEN_E2EE_BOOTSTRAP_PATH="$E2EE_BOOTSTRAP" \
    LIFLY_GOLDEN_PHONE_DB_PATH="$PHONE_DB" \
    flutter test test/live_golden_runtime_test.dart
)

echo "[golden 5/6] local E2EE candidate commit + encrypted audit + undo"
if [[ ! -s "$E2EE_BOOTSTRAP" ]]; then
  echo "Golden E2EE bootstrap was not produced" >&2
  exit 1
fi
smoke_output="$(cat "$E2EE_BOOTSTRAP" | "$E2EE_COMMIT_SMOKE")"
printf '%s\n' "$smoke_output"
printf '%s\n' "$smoke_output" | grep -Fq '"status":"pass"'
echo "GOLDEN_LOCAL_E2EE_COMMIT=PASS"

echo "[golden 6/6] result"
echo "GOLDEN_RUNTIME=PASS"
