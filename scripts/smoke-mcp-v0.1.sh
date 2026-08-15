#!/usr/bin/env bash
set -Eeuo pipefail

API_BASE="${LIFLY_API_BASE_URL:-http://localhost:8210}"
TMP_DIR="$(mktemp -d)"
LAST_BODY=""
PASS_COUNT=0

trap 'rm -rf "$TMP_DIR"' EXIT

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

  code="$(curl "${args[@]}")" || fail "$name request failed"
  LAST_BODY="$response_file"

  if [[ "$code" != "$expected_code" ]]; then
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

echo "Lifly MCP v0.1 smoke test"
echo "API_BASE=$API_BASE"
echo ""

RUN_ID="$(date +%Y%m%d%H%M%S)"

http_json "health" GET "/api/v1/health" 200
assert_jq '.status == "ok"' "health status should be ok"
pass "health"

http_json "memo_create" POST "/api/v1/mcp/memo/create" 200 "{\"type\":\"memo\",\"title\":\"MCP smoke memo $RUN_ID\",\"content_markdown\":\"created by scripts/smoke-mcp-v0.1.sh\",\"tags\":[\"mcp\",\"smoke\"]}"
MEMO_ID="$(jq -r '.memo_id' "$LAST_BODY")"
MEMO_UNDO_TOKEN="$(jq -r '.undo_token' "$LAST_BODY")"
[[ "$MEMO_ID" != "null" && -n "$MEMO_ID" ]] || fail "memo_create should return memo_id"
[[ "$MEMO_UNDO_TOKEN" != "null" && -n "$MEMO_UNDO_TOKEN" ]] || fail "memo_create should return undo_token"
assert_jq '.memo.status == "active"' "memo_create should return active memo"
pass "memo_create"

http_json "memo_search" POST "/api/v1/mcp/memo/search" 200 "{\"q\":\"MCP smoke memo $RUN_ID\",\"limit\":5}"
assert_jq '.memos | type == "array"' "memo_search should return memos array"
assert_jq_arg id "$MEMO_ID" '.memos | any(.id == $id)' "memo_search should find created memo"
pass "memo_search"

http_json "memo_create_invalid_type" POST "/api/v1/mcp/memo/create" 422 "{\"type\":\"invalid\",\"content_markdown\":\"bad\"}"
pass "memo_create invalid type -> 422"

http_json "expense_create" POST "/api/v1/mcp/expense/create" 200 "{\"amount\":12.34,\"currency\":\"CNY\",\"direction\":\"expense\",\"merchant\":\"MCP Smoke Merchant $RUN_ID\",\"note\":\"created by smoke script\"}"
TX_ID="$(jq -r '.transaction.id' "$LAST_BODY")"
[[ "$TX_ID" != "null" && -n "$TX_ID" ]] || fail "expense_create should return transaction.id"
assert_jq '.transaction.status == "active"' "expense_create should return active transaction"
pass "expense_create"

http_json "expense_create_invalid_amount" POST "/api/v1/mcp/expense/create" 422 "{\"amount\":0,\"currency\":\"CNY\",\"direction\":\"expense\"}"
pass "expense_create amount=0 -> 422"

http_json "expense_search" POST "/api/v1/mcp/expense/search" 200 "{\"q\":\"MCP Smoke Merchant $RUN_ID\",\"limit\":5}"
assert_jq '.transactions | type == "array"' "expense_search should return transactions array"
assert_jq_arg id "$TX_ID" '.transactions | any(.id == $id)' "expense_search should find created transaction"
pass "expense_search"

http_json "expense_summary" POST "/api/v1/mcp/expense/summary" 200 "{\"period\":\"current_month\"}"
assert_jq '.period == "current_month"' "expense_summary should return current_month"
assert_jq '.total_expense | type == "number"' "expense_summary should return numeric total_expense"
assert_jq '.count | type == "number"' "expense_summary should return numeric count"
pass "expense_summary"

http_json "task_create" POST "/api/v1/mcp/task/create" 200 "{\"title\":\"MCP smoke task $RUN_ID\",\"description\":\"created by smoke script\",\"priority\":\"normal\"}"
TASK_ID="$(jq -r '.task.id' "$LAST_BODY")"
[[ "$TASK_ID" != "null" && -n "$TASK_ID" ]] || fail "task_create should return task.id"
assert_jq '.task.task_status == "todo"' "task_create should return todo task"
pass "task_create"

http_json "task_list" POST "/api/v1/mcp/task/list" 200 "{\"task_status\":\"todo\",\"limit\":20}"
assert_jq '.tasks | type == "array"' "task_list should return tasks array"
assert_jq_arg id "$TASK_ID" '.tasks | any(.id == $id)' "task_list should find created task"
pass "task_list"

http_json "task_complete" POST "/api/v1/mcp/task/complete" 200 "{\"task_id\":\"$TASK_ID\"}"
assert_jq '.task.task_status == "done"' "task_complete should mark task as done"
assert_jq '.task.completed_at != null' "task_complete should set completed_at"
pass "task_complete"

http_json "task_complete_missing_task_id" POST "/api/v1/mcp/task/complete" 422 "{}"
pass "task_complete missing task_id -> 422"

http_json "asset_create_upload_url" POST "/api/v1/mcp/asset/create-upload-url" 200 "{\"filename\":\"mcp-smoke-$RUN_ID.txt\",\"mime_type\":\"text/plain\",\"size_bytes\":12,\"asset_type\":\"file\"}"
ASSET_ID="$(jq -r '.asset_id' "$LAST_BODY")"
[[ "$ASSET_ID" != "null" && -n "$ASSET_ID" ]] || fail "asset_create_upload_url should return asset_id"
assert_jq '.storage_key | startswith("attachments/local-dev/")' "asset_create_upload_url should return local-dev storage key"
assert_jq '.upload_url | type == "string" and length > 0' "asset_create_upload_url should return upload_url"
assert_jq '.asset.kind == "internal"' "asset_create_upload_url should return internal asset"
assert_jq '.asset.sync_status == "pending"' "asset_create_upload_url should return pending asset"
pass "asset_create_upload_url"

http_json "asset_create_upload_url_invalid_type" POST "/api/v1/mcp/asset/create-upload-url" 422 "{\"filename\":\"bad.txt\",\"asset_type\":\"invalid\"}"
pass "asset_create_upload_url invalid asset_type -> 422"

http_json "asset_register_external_url" POST "/api/v1/mcp/asset/register-external-url" 200 "{\"external_url\":\"https://example.com/lifly-mcp-smoke-$RUN_ID\",\"title\":\"MCP smoke external link $RUN_ID\",\"asset_type\":\"link\"}"
assert_jq '.asset.kind == "external"' "asset_register_external_url should return external asset"
assert_jq '.asset.sync_status == "synced"' "asset_register_external_url should return synced asset"
assert_jq '.asset.external_url | startswith("https://example.com/lifly-mcp-smoke-")' "asset_register_external_url should return external_url"
pass "asset_register_external_url"

http_json "capture_parse" POST "/api/v1/mcp/capture/parse" 200 "{\"text\":\"记一下 Lifly MCP smoke capture $RUN_ID\",\"timezone\":\"Asia/Shanghai\",\"locale\":\"zh-CN\"}"
CAPTURE_ID="$(jq -r '.capture_id' "$LAST_BODY")"
[[ "$CAPTURE_ID" != "null" && -n "$CAPTURE_ID" ]] || fail "capture_parse should return capture_id"
assert_jq '.actions | type == "array" and length >= 1' "capture_parse should return at least one action"
pass "capture_parse"

http_json "capture_commit" POST "/api/v1/mcp/capture/commit" 200 "{\"capture_id\":\"$CAPTURE_ID\"}"
CAPTURE_UNDO_TOKEN="$(jq -r '.undo_token' "$LAST_BODY")"
[[ "$CAPTURE_UNDO_TOKEN" != "null" && -n "$CAPTURE_UNDO_TOKEN" ]] || fail "capture_commit should return undo_token"
assert_jq '.committed == true' "capture_commit should return committed=true"
assert_jq '.created_entities | type == "array" and length >= 1' "capture_commit should create at least one entity"
pass "capture_commit"

http_json "capture_undo" POST "/api/v1/mcp/capture/undo" 200 "{\"undo_token\":\"$CAPTURE_UNDO_TOKEN\"}"
assert_jq '.undone >= 1' "capture_undo should undo at least one entity"
assert_jq '.failed_entities | type == "array" and length == 0' "capture_undo should have no failed entities"
pass "capture_undo"

http_json "capture_undo_reused_token" POST "/api/v1/mcp/capture/undo" 404 "{\"undo_token\":\"$CAPTURE_UNDO_TOKEN\"}"
pass "capture_undo reused token -> 404"

echo ""
echo "All Lifly MCP v0.1 smoke checks passed: $PASS_COUNT"
