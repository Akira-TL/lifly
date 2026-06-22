#!/bin/bash
set -e

API="http://localhost:8310/api/v1"

echo "=== 1. capture_parse — 混合输入解析 ==="
PARSE_RES=$(curl -s -X POST "$API/mcp/capture/parse" \
  -H "Content-Type: application/json" \
  -d '{"text":"今天中午食堂花了18，晚上8点提醒我改页面，记一下今天有点累","timezone":"Asia/Shanghai","locale":"zh-CN"}')
echo "$PARSE_RES" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d, indent=2, ensure_ascii=False))"
CAPTURE_ID=$(echo "$PARSE_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['capture_id'])")
echo "capture_id=$CAPTURE_ID"

echo -e "\n=== 2. capture_commit — 确认执行全部动作 ==="
COMMIT_RES=$(curl -s -X POST "$API/mcp/capture/commit" \
  -H "Content-Type: application/json" \
  -d "{\"capture_id\":\"$CAPTURE_ID\"}")
echo "$COMMIT_RES" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"
UNDO_TOKEN=$(echo "$COMMIT_RES" | python3 -c "import sys,json; print(json.load(sys.stdin).get('undo_token',''))")

echo -e "\n=== 3. capture_undo — 撤销 ==="
curl -s -X POST "$API/mcp/capture/undo" \
  -H "Content-Type: application/json" \
  -d "{\"undo_token\":\"$UNDO_TOKEN\"}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 4. memo_create ==="
curl -s -X POST "$API/mcp/memo/create" \
  -H "Content-Type: application/json" \
  -d '{"content_markdown":"MCP创建的备忘","title":"测试备忘","tags":["test","mcp"]}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 5. memo_search ==="
curl -s -X POST "$API/mcp/memo/search" \
  -H "Content-Type: application/json" \
  -d '{"q":"MCP"}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 6. expense_create ==="
curl -s -X POST "$API/mcp/expense/create" \
  -H "Content-Type: application/json" \
  -d '{"amount":25.5,"merchant":"星巴克","direction":"expense","note":"拿铁"}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 7. expense_search ==="
curl -s -X POST "$API/mcp/expense/search" \
  -H "Content-Type: application/json" \
  -d '{"q":"星巴克"}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 8. expense_summary ==="
curl -s -X POST "$API/mcp/expense/summary" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 9. task_create ==="
TASK_RES=$(curl -s -X POST "$API/mcp/task/create" \
  -H "Content-Type: application/json" \
  -d '{"title":"MCP测试任务","priority":"high","remind_at":"2026-06-22T20:00:00+08:00"}')
echo "$TASK_RES" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"
TASK_ID=$(echo "$TASK_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['task']['id'])")

echo -e "\n=== 10. task_list ==="
curl -s -X POST "$API/mcp/task/list" \
  -H "Content-Type: application/json" \
  -d '{}' | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 11. task_complete ==="
curl -s -X POST "$API/mcp/task/complete" \
  -H "Content-Type: application/json" \
  -d "{\"task_id\":\"$TASK_ID\"}" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"

echo -e "\n=== 全部测试完成 ==="
