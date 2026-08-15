#!/bin/bash
set -e

API="http://localhost:8210/api/v1"
PASS=0
FAIL=0

check() {
    if echo "$2" | grep -q "$3"; then
        echo "  ✅ $1"; PASS=$((PASS+1))
    else
        echo "  ❌ $1"; FAIL=$((FAIL+1))
    fi
}

echo "=== P6 搜索增强 & 首页统计 & 附件预览测试 ==="

# ── 1. 跨模块搜索 ──
echo -e "\n--- 1. 搜索「测试」---"
SR=$(curl -s "$API/search?q=测试")
echo "$SR" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:500])"
check "搜索结果有 items" '"items"' "$SR"
check "返回 q=测试" '"q":"测试"' "$SR"

# ── 2. 搜索账单 ──
echo -e "\n--- 2. 搜索「星巴克」（限定 ledger）---"
SR2=$(curl -s "$API/search?q=星巴克&entity_type=ledger")
echo "$SR2" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(f'count={d[\"total\"]}, first={d[\"items\"][0][\"title\"] if d[\"items\"] else \"none\"}')"
check "搜索结果有 ledger 类型" "ledger" "$SR2"

# ── 3. 首页统计 ──
echo -e "\n--- 3. 首页统计 ---"
DB=$(curl -s "$API/dashboard")
echo "$DB" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:600])"
check "包含 memo_total" "memo_total" "$DB"
check "包含 month_expense" "month_expense" "$DB"
check "包含 recent_transactions" "recent_transactions" "$DB"

# ── 4. 搜索空结果 ──
echo -e "\n--- 4. 搜索不存在的内容 ---"
SR3=$(curl -s "$API/search?q=不存在的搜搜词xyz")
echo "$SR3" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(f'total={d[\"total\"]}')"
check "总数为 0" '"total":0' "$SR3"

echo -e "\n=== 测试完成: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] || exit 1
