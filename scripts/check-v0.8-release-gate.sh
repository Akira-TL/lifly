#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

echo "[1/8] v0.7 产品地基回归"
bash scripts/check-v0.7-release-gate.sh

echo "[2/8] 主题协议与故障回退契约"
for contract in \
  "valid declarative package parses semantic manifest and tokens" \
  "runtime falls back to Core when package compatibility fails" \
  "failed update keeps the previous known-good version active" \
  "denied entitlement follows declared fallback then Core" \
  "cached known-good theme activates only after Core is available" \
  "Web dashboard profile extends the rail without losing modules" \
  "Phone shell keeps every destination touch target at least 48px"; do
  rg -Fq "$contract" apps/client_flutter/test \
    || fail "缺少主题框架回归测试：$contract"
done

echo "[3/8] Web Core-first 与默认/Wasm 构建门禁"
bash scripts/check-web-theme-performance.sh

echo "[4/8] Lifly Core 零远程依赖"
core_theme="apps/client_flutter/lib/app/theme/app_theme.dart"
if rg -n 'https?://|AssetImage|NetworkImage' "$core_theme"; then
  fail "Lifly Core 依赖远程或装饰资源"
fi
if rg -n "fontFamily: [\"']" "$core_theme"; then
  fail "Lifly Core 依赖自定义字体"
fi
rg -Fq "fontFamily: null" "$core_theme" \
  || fail "Lifly Core 未明确使用系统字体"

echo "[5/8] 页面与主题框架边界"
if rg -n \
  'app/theme/(theme_tokens|theme_package_resolver|app_theme|theme_platform_profile)\.dart' \
  apps/client_flutter/lib/features; then
  fail "业务页面直接依赖主题包解析或底层 Token"
fi
if rg -n 'lifly\.test\.|ThemePackage\.fromJson' apps/client_flutter/lib/features; then
  fail "业务页面包含测试主题或主题包解析分支"
fi

echo "[6/8] 启动与安全契约"
for mark in \
  lifly-host-feedback \
  lifly-entrypoint-loaded \
  lifly-engine-initialized \
  lifly-dart-entrypoint \
  lifly-flutter-first-frame \
  lifly-core-usable \
  lifly-theme-activated; do
  rg -Fq "$mark" apps/client_flutter/web apps/client_flutter/lib/app/startup \
    || fail "缺少启动里程碑：$mark"
done
rg -Fq "Theme Package Cache" doc/architecture/theme-application-framework.md \
  || fail "主题缓存架构未回写"
rg -Fq "没有配置生产公钥或正式验证器时默认拒绝远程主题" \
  doc/architecture/theme-application-framework.md \
  || fail "生产签名默认拒绝边界未回写"

echo "[7/8] 正式文档与临时计划清理"
for document in \
  doc/architecture/theme-application-framework.md \
  doc/design/client-app.md \
  doc/design/ui-information-architecture.md \
  doc/guide/testing-quality.md \
  doc/guide/roadmap.md \
  doc/guide/current-status.md \
  doc/guide/pending-tasks.md; do
  [[ -s "$document" ]] || fail "正式文档缺失：$document"
done
[[ ! -e doc/plan/theme-application-framework.md ]] \
  || fail "已完成的主题框架临时计划尚未删除"
rg -Fq "scripts/check-v0.8-release-gate.sh" doc/guide/testing-quality.md \
  || fail "测试文档未登记 v0.8 发布门禁"

echo "[8/8] Git 差异与文件体积"
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
git diff --check

echo "v0.8.0 cross-platform theme application framework release gate passed."
