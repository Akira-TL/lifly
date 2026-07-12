#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

echo "[1/7] 服务端检查"
bash scripts/check-api.sh

echo "[2/7] Flutter 检查"
bash scripts/check-client-flutter.sh

echo "[3/7] PowerSync 同步范围"
bash scripts/check-powersync-sync-scope.sh

echo "[4/7] 源码体积边界"
oversized=0
while IFS= read -r file; do
  lines="$(wc -l < "$file")"
  if (( lines > 800 )); then
    echo "[FAIL] $file: $lines 行，超过 800 行"
    oversized=1
  fi
done < <(
  find apps/client_flutter/lib services/api/app \
    -type f \( -name '*.dart' -o -name '*.py' \) | sort
)
(( oversized == 0 )) || fail "存在超过体积边界的 Dart/Python 文件"

echo "[5/7] 假数据与占位入口"
if rg -n "placeholder-file" apps/client_flutter/lib services/api/app; then
  fail "仍存在附件占位上传入口"
fi
for placeholder in \
  '"sync_summary": "api_available"' \
  "'sync_summary': 'api_available'" \
  '"import_summary": "idle"' \
  "'import_summary': 'idle'" \
  '"settings_summary": "ok"' \
  "'settings_summary': 'ok'"; do
  if rg -n -F "$placeholder" apps/client_flutter/lib services/api/app; then
    fail "仍存在首页状态摘要固定占位值：$placeholder"
  fi
done

echo "[6/7] 离线与云端失败回退契约"
rg -q "HomeOverviewRepository falls back to Local Core when cloud load fails" \
  apps/client_flutter/test/repository_local_mode_test.dart \
  || fail "缺少首页云端失败后本地回退测试"
rg -q "LedgerRepository falls back to Local Core when cloud overview fails" \
  apps/client_flutter/test/repository_local_mode_test.dart \
  || fail "缺少记账概览云端失败后本地回退测试"
rg -q "AI capture keeps continuous turns and supports undo then revise" \
  apps/client_flutter/test/ai_capture_service_test.dart \
  || fail "缺少 AI Capture 本地连续会话测试"

echo "[7/7] 发布文档与 Git 差异"
[[ ! -e doc/plan/mobile-product-foundation.md ]] \
  || fail "已完成的 mobile product foundation 计划文档尚未删除"
git diff --check

echo "v0.7.0 product foundation release gate passed."
