#!/usr/bin/env bash
set -Eeuo pipefail

API_BASE="${LIFLY_API_BASE_URL:-http://localhost:8210}"
TMP_DIR="$(mktemp -d)"
LAST_BODY=""
PASS_COUNT=0

fail() {
  echo ""
  echo "[FAIL] $*" >&2
  if [[ -n "${LAST_BODY:-}" && -f "$LAST_BODY" ]]; then
    echo "[response]" >&2
    cat "$LAST_BODY" >&2 || true
    echo "" >&2
  fi
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

http_json() {
  local name="$1"
  local method="$2"
  local path="$3"
  local expected_code="$4"
  local body="${5-__NO_BODY__}"
  local response_file="$TMP_DIR/$(echo "$name" | tr -c 'A-Za-z0-9_' '_').json"
  local code

  local args=(-sS -o "$response_file" -w "%{http_code}" -X "$method" "$API_BASE$path")
  if [[ "$body" != "__NO_BODY__" ]]; then
    args+=(-H "Content-Type: application/json" -d "$body")
  fi

  code="$(curl "${args[@]}")" || {
    if [[ "$name" == "health" ]]; then
      return 1
    fi
    fail "$name request failed"
  }
  LAST_BODY="$response_file"

  if [[ "$code" != "$expected_code" ]]; then
    if [[ "$name" == "health" ]]; then
      return 1
    fi
    fail "$name expected HTTP $expected_code, got HTTP $code"
  fi
}

assert_jq() {
  local expr="$1"
  local message="$2"
  jq -e "$expr" "$LAST_BODY" >/dev/null || fail "$message"
}

assert_jq_arg() {
  local arg_name="$1"
  local arg_value="$2"
  local expr="$3"
  local message="$4"
  jq -e --arg "$arg_name" "$arg_value" "$expr" "$LAST_BODY" >/dev/null || fail "$message"
}

require_cmd curl
require_cmd jq

echo "Lifly sync v0.3 smoke test"
echo "API_BASE=$API_BASE"
echo ""

RUN_ID="$(date -u +%y%m%d%H%M%S)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLIENT_ID="lifly-sync-smoke-$RUN_ID"
MEMO_ID="smk-m-$RUN_ID"
TASK_ID="smk-t-$RUN_ID"
TX_ID="smk-x-$RUN_ID"
MEMO_TITLE="Sync smoke memo $RUN_ID"
TASK_TITLE="Sync smoke task $RUN_ID"
MERCHANT="Sync Smoke Merchant $RUN_ID"

for attempt in {1..30}; do
  if http_json "health" GET "/api/v1/health" 200; then
    break
  fi
  if [[ "$attempt" == "30" ]]; then
    fail "health request failed after 30 attempts"
  fi
  sleep 1
done
assert_jq '.status == "ok"' "health status should be ok"
pass "health"

http_json "sync_credentials" GET "/api/v1/sync/credentials" 200
assert_jq '.success == true' "sync credentials should return success=true"
assert_jq '.data.endpoint | type == "string" and length > 0' "sync credentials should return endpoint"
assert_jq '.data.token | type == "string" and length > 0' "sync credentials should return token"
assert_jq '.data.user_id == "local-dev"' "sync credentials should return local-dev user"
assert_jq '.data.mode == "development"' "sync credentials should return development mode"
assert_jq '.data.expires_at | type == "string" and length > 0' "sync credentials should return expires_at"
pass "sync_credentials"

SYNC_BODY="$(jq -n \
  --arg client_id "$CLIENT_ID" \
  --arg memo_id "$MEMO_ID" \
  --arg task_id "$TASK_ID" \
  --arg tx_id "$TX_ID" \
  --arg memo_title "$MEMO_TITLE" \
  --arg task_title "$TASK_TITLE" \
  --arg merchant "$MERCHANT" \
  --arg now "$NOW" \
  '{
    client_id: $client_id,
    changes: [
      {
        entity_type: "memo",
        operation: "upsert",
        entity_id: $memo_id,
        user_id: "local-dev",
        revision: 1,
        created_at: $now,
        updated_at: $now,
        source: "powersync",
        data: {
          type: "memo",
          title: $memo_title,
          content_markdown: "created by scripts/smoke-sync-v0.3.sh",
          tags: ["sync", "smoke"],
          status: "active",
          source: "powersync"
        }
      },
      {
        entity_type: "task",
        operation: "upsert",
        entity_id: $task_id,
        user_id: "local-dev",
        revision: 1,
        created_at: $now,
        updated_at: $now,
        source: "powersync",
        data: {
          title: $task_title,
          description: "created by scripts/smoke-sync-v0.3.sh",
          priority: "normal",
          task_status: "todo",
          status: "active",
          source: "powersync"
        }
      },
      {
        entity_type: "expense",
        operation: "upsert",
        entity_id: $tx_id,
        user_id: "local-dev",
        revision: 1,
        created_at: $now,
        updated_at: $now,
        source: "powersync",
        data: {
          direction: "expense",
          amount: 12.34,
          currency: "CNY",
          merchant: $merchant,
          note: "created by scripts/smoke-sync-v0.3.sh",
          occurred_at: $now,
          status: "active",
          source: "powersync"
        }
      }
    ]
  }')"

http_json "sync_push" POST "/api/v1/sync/push" 200 "$SYNC_BODY"
assert_jq '.success == true' "sync push should return success=true"
assert_jq '.data.applied == 3' "sync push should apply 3 changes"
assert_jq '.data.skipped == 0' "sync push should skip 0 changes"
assert_jq '.data.results | length == 3' "sync push should return 3 results"
assert_jq '.data.results | all(.status == "applied")' "sync push results should all be applied"
pass "sync_push memo/task/expense"

http_json "memo_readback" GET "/api/v1/memos/$MEMO_ID" 200
assert_jq_arg title "$MEMO_TITLE" '.data.title == $title' "memo readback should match title"
assert_jq '.data.status == "active"' "memo readback should be active"
pass "memo_readback"

http_json "task_readback" GET "/api/v1/tasks/$TASK_ID" 200
assert_jq_arg title "$TASK_TITLE" '.data.title == $title' "task readback should match title"
assert_jq '.data.task_status == "todo"' "task readback should be todo"
pass "task_readback"

http_json "expense_readback" GET "/api/v1/ledger/transactions/$TX_ID" 200
assert_jq_arg merchant "$MERCHANT" '.data.merchant == $merchant' "expense readback should match merchant"
assert_jq '.data.amount == 12.34' "expense readback should match amount"
pass "expense_readback"

http_json "sync_push_stale" POST "/api/v1/sync/push" 200 "$SYNC_BODY"
assert_jq '.data.applied == 0' "stale sync push should apply 0 changes"
assert_jq '.data.skipped == 3' "stale sync push should skip 3 changes"
assert_jq '.data.results | all(.status == "skipped" and .reason == "stale_revision")' "stale sync push should report stale_revision"
pass "sync_push stale revision -> skipped"

echo ""
echo "All Lifly sync v0.3 smoke checks passed: $PASS_COUNT"
