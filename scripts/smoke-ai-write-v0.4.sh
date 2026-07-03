#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://127.0.0.1:8310}"
API_V1="$API_BASE/api/v1"
RUN_ID="$(date +%s)"

post_json() {
  local path="$1"
  local body="$2"
  curl -fsS \
    -H 'Content-Type: application/json' \
    -H "X-Request-ID: smoke-ai-write-v0.4-$RUN_ID" \
    -X POST \
    "$API_V1$path" \
    -d "$body"
}

get_json() {
  local path="$1"
  curl -fsS "$API_V1$path"
}

require_contains() {
  local haystack="$1"
  local needle="$2"
  local name="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "[FAIL] $name missing: $needle" >&2
    echo "$haystack" >&2
    exit 1
  fi
  echo "[PASS] $name"
}

echo "Lifly v0.4 AI Write smoke"
echo "API_BASE=$API_BASE"

health="$(get_json '/health')"
require_contains "$health" 'ok' 'health'

memo="$(post_json '/mcp/memo/create' '{"type":"memo","title":"v0.4 smoke memo","content_markdown":"created by v0.4 smoke","tags":["smoke","ai"]}')"
require_contains "$memo" 'undo_token' 'memo_create undo_token'

parse="$(post_json '/mcp/capture/parse' '{"text":"在食堂花了18元，提醒我晚上复盘，记一下今天状态不错 https://example.com/lifly","timezone":"Asia/Shanghai","locale":"zh-CN"}')"
require_contains "$parse" 'capture_id' 'capture_parse capture_id'
require_contains "$parse" 'actions' 'capture_parse actions'

capture_id="$(printf '%s' "$parse" | python3 -c 'import json,sys; print(json.load(sys.stdin)["capture_id"])')"
commit="$(post_json '/mcp/capture/commit' "{\"capture_id\":\"$capture_id\",\"selected_action_indexes\":[0,1]}")"
require_contains "$commit" 'created_entities' 'capture_commit created_entities'
require_contains "$commit" 'failed_actions' 'capture_commit failed_actions'
require_contains "$commit" 'undo_token' 'capture_commit undo_token'

undo_token="$(printf '%s' "$commit" | python3 -c 'import json,sys; print(json.load(sys.stdin)["undo_token"])')"
undo="$(post_json '/mcp/capture/undo' "{\"undo_token\":\"$undo_token\"}")"
require_contains "$undo" 'undone' 'capture_undo undone'
require_contains "$undo" 'entities' 'capture_undo entities'

repeat_undo="$(post_json '/mcp/capture/undo' "{\"undo_token\":\"$undo_token\"}")"
require_contains "$repeat_undo" '"undone":0' 'capture_undo idempotent'

audit="$(get_json '/audit/ai-summary')"
require_contains "$audit" 'capture_commit' 'ai audit summary capture_commit'

echo "v0.4 AI Write smoke passed"
