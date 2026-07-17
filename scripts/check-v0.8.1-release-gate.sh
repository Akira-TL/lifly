#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

echo "[1/8] Flutter 客户端完整检查"
bash scripts/check-client-flutter.sh

echo "[2/8] Web Shell 导航与状态契约"
for contract in \
  "Web shell exposes global actions and persists sidebar collapse" \
  "Web shell shortcuts yield to focused text inputs" \
  "Web theme switch preserves the selected destination and API" \
  "Desktop compact profile keeps a narrow keyboard-ready rail" \
  "Phone shell keeps every destination touch target at least 48px"; do
  rg -Fq "$contract" apps/client_flutter/test/widget_test.dart \
    || fail "缺少 Shell 回归测试：$contract"
done

for state in LoadingState EmptyState ErrorState OfflineState; do
  rg -Fq "class $state" apps/client_flutter/lib/shared/widgets/async_content.dart \
    || fail "缺少共享页面状态：$state"
done
rg -Fq "asset library consumes the shared empty state" \
  apps/client_flutter/test/asset_list_page_test.dart \
  || fail "共享页面状态没有真实业务消费测试"

echo "[3/8] 全局管理入口与核心导航边界"
for destination in 首页 备忘 AI 记账 任务; do
  rg -Fq "label: '$destination'" apps/client_flutter/lib/app/shell/app_shell.dart \
    || fail "缺少核心入口：$destination"
done
for entry in 账单导入 导入批次 数据导出 附件库 设置与诊断; do
  rg -Fq "title: '$entry'" \
    apps/client_flutter/lib/features/management/pages/management_hub_page.dart \
    || fail "管理中心缺少入口：$entry"
done
if rg -n \
  "^import 'package:client_flutter/(data|domain)/|local_core|powersync" \
  apps/client_flutter/lib/features/management/pages/management_hub_page.dart; then
  fail "管理中心直接依赖业务或数据实现层"
fi

rg -Fq "lifly.shell.destination_index" \
  apps/client_flutter/lib/app/shell/shell_preferences.dart \
  || fail "当前核心入口没有设备本地持久化"
rg -Fq "_EditableAwareAction" apps/client_flutter/lib/app/shell/wide_shell.dart \
  || fail "全局快捷键没有输入焦点保护"

echo "[4/8] 主题与业务页面边界"
if rg -n \
  'app/theme/(theme_tokens|theme_package_resolver|app_theme|theme_platform_profile)\.dart' \
  apps/client_flutter/lib/features; then
  fail "业务页面直接依赖主题包解析或底层 Token"
fi
if rg -n 'lifly\.test\.|ThemePackage\.fromJson' apps/client_flutter/lib/features; then
  fail "业务页面包含测试主题或主题包解析分支"
fi

echo "[5/8] 默认 Web 与 Wasm 构建门禁"
LIFLY_APP_VERSION=0.8.1 bash scripts/check-web-theme-performance.sh

echo "[6/8] CI 与发布文档"
rg -Fq "scripts/check-v0.8.1-release-gate.sh" .github/workflows/ci.yml \
  || fail "CI 未接入 v0.8.1 发布门禁"
for document in \
  doc/design/client-app.md \
  doc/design/ui-information-architecture.md \
  doc/guide/testing-quality.md \
  doc/guide/roadmap.md \
  doc/guide/current-status.md \
  doc/guide/pending-tasks.md; do
  [[ -s "$document" ]] || fail "正式文档缺失：$document"
done
rg -Fq "scripts/check-v0.8.1-release-gate.sh" doc/guide/testing-quality.md \
  || fail "测试文档未登记 v0.8.1 发布门禁"
rg -Fq "管理中心" doc/design/ui-information-architecture.md \
  || fail "UI 信息架构未回写全局管理入口"
rg -Fq "共享页面状态" doc/design/client-app.md \
  || fail "客户端设计未回写共享页面状态"

[[ ! -e doc/plan/web-shell-navigation.md ]] \
  || fail "已完成的 Web Shell 临时计划尚未删除"

echo "[7/8] 源码体积与视觉规则边界"
oversized=0
while IFS= read -r file; do
  lines="$(wc -l < "$file")"
  if (( lines > 800 )); then
    echo "[FAIL] $file: $lines 行，超过 800 行"
    oversized=1
  fi
done < <(
  find apps/client_flutter/lib \
    -type f -name '*.dart' | sort
)
(( oversized == 0 )) || fail "存在超过体积边界的 Dart 文件"

if rg -n "Color\(0x|Colors\.(red|green|blue|orange|purple)" \
  apps/client_flutter/lib/app/shell \
  apps/client_flutter/lib/features/management \
  apps/client_flutter/lib/shared/widgets/async_content.dart; then
  fail "Web Shell 或共享状态绕过主题系统硬编码颜色"
fi

echo "[8/8] Git 差异"
git diff --check

echo "v0.8.1 Web shell and global navigation release gate passed."
