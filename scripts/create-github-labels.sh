#!/usr/bin/env bash
set -euo pipefail

REPO="${1:?Usage: ./scripts/create-github-labels.sh owner/repo}"

create_label() {
  local name="$1" color="$2" desc="$3"
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force
}

create_label "type:spike" "C5DEF5" "技术验证"
create_label "type:feature" "0E8A16" "功能"
create_label "type:bug" "D73A4A" "缺陷"
create_label "type:docs" "0075CA" "文档"
create_label "type:infra" "5319E7" "基础设施"

for area in repo client backend mcp sync asset ledger memo task import security; do
  create_label "area:$area" "BFDADC" "Area $area"
done

for agent in architect client backend mcp qa devops docs; do
  create_label "agent:$agent" "F9D0C4" "Agent $agent"
done

create_label "priority:p0" "B60205" "最高优先级"
create_label "priority:p1" "D93F0B" "高优先级"
create_label "priority:p2" "FBCA04" "普通优先级"
create_label "status:ready" "0E8A16" "可执行"
create_label "status:blocked" "D73A4A" "被阻塞"
create_label "needs-architecture-decision" "000000" "需要架构决策"
