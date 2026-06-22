#!/bin/bash
set -e

API="http://localhost:8310/api/v1/imexport"
PASS=0
FAIL=0

check() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if echo "$actual" | grep -q "$expected"; then
        echo "  ✅ $label"
        PASS=$((PASS+1))
    else
        echo "  ❌ $label — expected '$expected', got: $(echo "$actual" | head -1)"
        FAIL=$((FAIL+1))
    fi
}

echo "=== P5 导入导出测试 ==="

# ── 1. 上传通用 CSV ──
echo -e "\n--- 1. 上传通用 CSV ---"
TMP_CSV=/tmp/p5-test.csv
echo "occurred_at,direction,amount,currency,merchant,note
2026-06-21 12:00,expense,18,CNY,食堂,午饭
2026-06-21 18:30,expense,35.5,CNY,超市,日用品" > "$TMP_CSV"
UPLOAD_RES=$(curl -s -F "file=@$TMP_CSV" "$API/import/upload?provider=generic")
echo "$UPLOAD_RES" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False)[:400])"
BATCH_ID=$(echo "$UPLOAD_RES" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['batch_id'])" 2>/dev/null || echo "")
check "batch_id 非空" "-" "$BATCH_ID"
check "batch_id 长度36" "36" "$(echo -n "$BATCH_ID" | wc -c)"
check "total_rows=2" '"total_rows":2' "$UPLOAD_RES"

# ── 2. 预览 ──
echo -e "\n--- 2. 预览批次 ---"
PREVIEW=$(curl -s "$API/import/$BATCH_ID/preview?limit=50")
echo "$PREVIEW" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:400])"
check "预览返回 total" '"total"' "$PREVIEW"

# ── 3. 批次详情 ──
echo -e "\n--- 3. 批次详情 ---"
DETAIL=$(curl -s "$API/import/$BATCH_ID")
echo "$DETAIL" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:300])"
check "status=preview" '"preview"' "$DETAIL"

# ── 4. Commit ──
echo -e "\n--- 4. Commit 批次 ---"
COMMIT=$(curl -s -X POST "$API/import/$BATCH_ID/commit")
echo "$COMMIT" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"
check "imported=2" '"imported":2' "$COMMIT"

# ── 5. 重复上传检测 ──
echo -e "\n--- 5. 重复上传检测 ---"
DUP_RES=$(curl -s -F "file=@$TMP_CSV" "$API/import/upload?provider=generic")
echo "$DUP_RES" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False)[:300])"
check "重复文件拒绝" "detail" "$DUP_RES"

# ── 6. Rollback ──
echo -e "\n--- 6. 批次回滚 ---"
ROLLBACK=$(curl -s -X POST "$API/import/$BATCH_ID/rollback")
echo "$ROLLBACK" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))"
check "rolled_back=2" '"rolled_back":2' "$ROLLBACK"

# ── 7. 批次列表 ──
echo -e "\n--- 7. 批次列表 ---"
BATCHES=$(curl -s "$API/import/batches")
echo "$BATCHES" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:400])"
check "批次列表有数据" '"items"' "$BATCHES"

# ── 8. 导出 CSV ──
echo -e "\n--- 8. 导出账单 CSV ---"
EXPORT_CSV=$(curl -s -X POST "$API/export" -H "Content-Type: application/json" -d '{"entity_type":"ledger_transactions","format":"csv"}')
echo "$EXPORT_CSV" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data'], indent=2, ensure_ascii=False)[:300])"
check "导出包含 preview" '"preview"' "$EXPORT_CSV"

# ── 9. 导出 Markdown ──
echo -e "\n--- 9. 导出备忘 Markdown ---"
EXPORT_MD=$(curl -s -X POST "$API/export" -H "Content-Type: application/json" -d '{"entity_type":"memos","format":"md"}')
echo "$EXPORT_MD" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print('size:', d['size_bytes'])"
check "备忘导出 size_bytes" '"size_bytes"' "$EXPORT_MD"

# ── 10. 导出全量 JSON ──
echo -e "\n--- 10. 导出全量 JSON ---"
EXPORT_ALL=$(curl -s -X POST "$API/export" -H "Content-Type: application/json" -d '{"entity_type":"all","format":"json"}')
echo "$EXPORT_ALL" | python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print('size:', d['size_bytes'], 'preview:', d['preview'][:100])"
check "全量导出包含 version" "version" "$EXPORT_ALL"

# ── 11. 流式导出 ──
echo -e "\n--- 11. 流式导出 ---"
STREAM=$(curl -s -o /dev/null -w "%{http_code}" "$API/export/stream?entity_type=all")
check "流式导出 HTTP 200" "200" "$STREAM"

echo -e "\n=== 测试完成: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] || exit 1
