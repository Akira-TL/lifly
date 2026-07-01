#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Lifly Local MCP v0.1 smoke test"

pnpm --filter @lifly/local-mcp build >/dev/null

OUT_FILE="$(mktemp)"
DIST_PROTOCOL_DIR="$ROOT_DIR/services/local-mcp/dist/packages/protocol"
mkdir -p "$DIST_PROTOCOL_DIR"
ln -sfn "$ROOT_DIR/packages/protocol/node_modules" "$DIST_PROTOCOL_DIR/node_modules"
trap 'rm -f "$OUT_FILE" "$DIST_PROTOCOL_DIR/node_modules"' EXIT

RUN_ID="$(date +%s)"

node services/local-mcp/dist/services/local-mcp/src/index.js >"$OUT_FILE" <<EOF
{"id":"health","method":"health"}
{"id":"tools","method":"tools/list"}
{"id":"memo_create","method":"tools/call","params":{"name":"memo_create","input":{"type":"memo","title":"Local MCP smoke memo $RUN_ID","content_markdown":"created by scripts/smoke-local-mcp-v0.1.sh","tags":["local","smoke"]}}}
{"id":"memo_search","method":"tools/call","params":{"name":"memo_search","input":{"q":"Local MCP smoke memo $RUN_ID","limit":5}}}
{"id":"memo_create_invalid","method":"tools/call","params":{"name":"memo_create","input":{"type":"invalid","content_markdown":"bad"}}}
{"id":"expense_create","method":"tools/call","params":{"name":"expense_create","input":{"amount":12.34,"currency":"CNY","direction":"expense","merchant":"Local MCP Smoke Merchant $RUN_ID","note":"created by local smoke script"}}}
{"id":"expense_search","method":"tools/call","params":{"name":"expense_search","input":{"q":"Local MCP Smoke Merchant $RUN_ID","limit":5}}}
{"id":"expense_summary","method":"tools/call","params":{"name":"expense_summary","input":{"period":"current_month"}}}
{"id":"task_create","method":"tools/call","params":{"name":"task_create","input":{"title":"Local MCP smoke task $RUN_ID","description":"created by local smoke script","priority":"normal"}}}
{"id":"task_list","method":"tools/call","params":{"name":"task_list","input":{"task_status":"todo","limit":20}}}
{"id":"task_complete","method":"tools/call","params":{"name":"task_complete","input":{"task_id":"local_task_0001"}}}
{"id":"asset_register_external_url","method":"tools/call","params":{"name":"asset_register_external_url","input":{"external_url":"https://example.com/lifly-local-mcp-smoke-$RUN_ID","title":"Local MCP smoke external link $RUN_ID","asset_type":"link"}}}
{"id":"capture_parse","method":"tools/call","params":{"name":"capture_parse","input":{"text":"记一下 Local MCP smoke capture $RUN_ID","timezone":"Asia/Shanghai","locale":"zh-CN"}}}
{"id":"capture_commit","method":"tools/call","params":{"name":"capture_commit","input":{"capture_id":"local_capture_0001"}}}
{"id":"capture_undo","method":"tools/call","params":{"name":"capture_undo","input":{"undo_token":"local_undo_0001"}}}
EOF

line() {
  sed -n "$1p" "$OUT_FILE"
}

assert_jq() {
  local body="$1"
  local expr="$2"
  local message="$3"
  echo "$body" | jq -e "$expr" >/dev/null || {
    echo "[FAIL] $message" >&2
    echo "$body" >&2
    exit 1
  }
}

pass() {
  echo "[PASS] $1"
}

BODY="$(line 1)"
assert_jq "$BODY" '.ok == true and .result.status == "ok" and .result.mode == "fake"' "health should return fake ok"
pass "local_mcp_health"

BODY="$(line 2)"
assert_jq "$BODY" '.ok == true and (.result.tools | any(.name == "memo_create")) and (.result.tools | any(.name == "capture_commit"))' "tools/list should include protocol tools"
pass "tools_list"

BODY="$(line 3)"
MEMO_ID="$(echo "$BODY" | jq -r '.result.memo_id')"
[[ "$MEMO_ID" == "local_memo_0001" ]] || { echo "[FAIL] memo_create should return local_memo_0001" >&2; echo "$BODY" >&2; exit 1; }
pass "memo_create"

BODY="$(line 4)"
assert_jq "$BODY" '.ok == true and (.result.memos | any(.id == "local_memo_0001"))' "memo_search should find created memo"
pass "memo_search"

BODY="$(line 5)"
assert_jq "$BODY" '.ok == false' "invalid memo type should fail"
pass "memo_create invalid type -> error"

BODY="$(line 6)"
assert_jq "$BODY" '.ok == true and .result.transaction.id == "local_tx_0001" and .result.transaction.status == "active"' "expense_create should return active transaction"
pass "expense_create"

BODY="$(line 7)"
assert_jq "$BODY" '.ok == true and (.result.transactions | any(.id == "local_tx_0001"))' "expense_search should find created transaction"
pass "expense_search"

BODY="$(line 8)"
assert_jq "$BODY" '.ok == true and .result.period == "current_month" and .result.total_expense == 12.34 and .result.count == 1' "expense_summary should summarize created transaction"
pass "expense_summary"

BODY="$(line 9)"
assert_jq "$BODY" '.ok == true and .result.task.id == "local_task_0001" and .result.task.task_status == "todo"' "task_create should return todo task"
pass "task_create"

BODY="$(line 10)"
assert_jq "$BODY" '.ok == true and (.result.tasks | any(.id == "local_task_0001"))' "task_list should find created task"
pass "task_list"

BODY="$(line 11)"
assert_jq "$BODY" '.ok == true and .result.task.task_status == "done" and .result.task.completed_at != null' "task_complete should mark task done"
pass "task_complete"

BODY="$(line 12)"
assert_jq "$BODY" '.ok == true and .result.asset.kind == "external" and .result.asset.sync_status == "synced"' "asset_register_external_url should return synced external asset"
pass "asset_register_external_url"

BODY="$(line 13)"
assert_jq "$BODY" '.ok == true and .result.capture_id == "local_capture_0001" and (.result.actions | length >= 1)' "capture_parse should return a capture session"
pass "capture_parse"

BODY="$(line 14)"
assert_jq "$BODY" '.ok == true and .result.committed == true and .result.undo_token == "local_undo_0001" and (.result.created_entities | length >= 1)' "capture_commit should commit capture actions"
pass "capture_commit"

BODY="$(line 15)"
assert_jq "$BODY" '.ok == true and .result.undone >= 1 and (.result.failed_entities | length == 0)' "capture_undo should undo committed entities"
pass "capture_undo"

echo
echo "All Lifly Local MCP v0.1 smoke checks passed: 15"
