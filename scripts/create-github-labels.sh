#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   gh auth login
#   ./scripts/create-github-labels.sh Akira-TL/lifly

REPO="${1:?Usage: ./scripts/create-github-labels.sh owner/repo}"

create_label() {
  local name="$1"
  local color="$2"
  local desc="$3"
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force
}

echo "Syncing labels for $REPO"

# Types
create_label "type:spike" "C5DEF5" "技术验证"
create_label "type:feature" "0E8A16" "功能"
create_label "type:bug" "D73A4A" "缺陷"
create_label "type:docs" "0075CA" "文档"
create_label "type:infra" "5319E7" "基础设施"
create_label "type:refactor" "FBCA04" "重构"
create_label "type:test" "1D76DB" "测试"

# Areas
for area in repo client backend mcp sync asset ledger memo task import security devops docs protocol; do
  create_label "area:$area" "BFDADC" "Area $area"
done

# Agents
for agent in architect client backend mcp sync asset import qa devops docs; do
  create_label "agent:$agent" "F9D0C4" "Agent $agent"
done

# Priority
create_label "priority:p0" "B60205" "最高优先级"
create_label "priority:p1" "D93F0B" "高优先级"
create_label "priority:p2" "FBCA04" "普通优先级"

# Status
create_label "status:ready" "0E8A16" "可执行"
create_label "status:in-progress" "0052CC" "执行中"
create_label "status:review" "5319E7" "等待审查"
create_label "status:blocked" "D73A4A" "被阻塞"

# Governance
create_label "needs-architecture-decision" "000000" "需要架构决策"
create_label "needs-local-validation" "D4C5F9" "需要本地环境验证"
create_label "risk:data-loss" "B60205" "可能影响数据安全"
create_label "risk:sync" "D93F0B" "可能影响同步"
create_label "risk:security" "B60205" "可能影响安全边界"

echo "Done."
