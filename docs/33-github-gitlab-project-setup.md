# 33. GitHub / GitLab 项目设置

## 1. 目标

把 Lifly 仓库设置成 AI agent 可执行、可审查、可追踪的工程环境。

本项目不依赖人类会议同步，而是依赖：

```text
文档
Issue
PR 模板
Milestone
Label
ADR
CI
```

## 2. GitHub 设置建议

### 2.1 Branch Protection

保护分支：

```text
master
```

建议规则：

```text
禁止直接 push master
必须通过 Pull Request
CI 通过后才能 merge
禁止 force push
禁止删除 protected branch
```

如果仓库仍处在早期快速初始化阶段，可以暂时允许管理员绕过，但 M0 结束后建议开启强保护。

### 2.2 Labels

使用 `.github/labels.yml` 中的标签。

核心标签：

```text
type:feature
type:bug
type:docs
type:infra
type:spike

area:client
area:backend
area:mcp
area:sync
area:asset
area:ledger
area:memo
area:task
area:import
area:security

agent:client
agent:backend
agent:mcp
agent:devops
agent:qa
agent:docs
agent:architect

priority:p0
priority:p1
priority:p2
status:ready
status:blocked
needs-architecture-decision
```

### 2.3 Milestones

创建：

```text
M0 Repo Bootstrap & Technical Spikes
M1 Local Data MVP
M2 Cloud Sync MVP
M3 Cloud MCP MVP
M4 Assets & Import MVP
M5 Windows Local MCP
```

### 2.4 Project Board

建议建立 GitHub Project：

```text
Lifly v0.1
```

字段：

```text
Status: Ready / In Progress / Review / Done / Blocked
Agent: Architect / Client / Backend / MCP / Sync / Asset / Import / QA / DevOps / Docs
Area
Priority
Milestone
```

## 3. GitLab 设置建议

如果使用 GitLab：

- Issue Templates 对应 `.gitlab/issue_templates/`；
- Merge Request Template 对应 `.gitlab/merge_request_templates/`；
- Labels 与 Milestones 同 GitHub；
- Protected Branch 启用 `master`；
- CI 使用 `.gitlab-ci.yml`。

## 4. Issue 创建原则

每个 Issue 是 AI agent 的任务合同。Issue 不应只有一句话。

必须包含：

```text
Goal
Context
Scope
Allowed files
Forbidden changes
Acceptance criteria
Validation
Related docs
```

## 5. PR 创建原则

PR 必须小。每个 PR 最好对应一个 Issue。

禁止把以下内容混在一个 PR：

```text
架构改动 + 业务实现
UI 重构 + 数据模型变更
MCP schema 修改 + 客户端页面修改
依赖升级 + 功能实现
```

## 6. AI Agent 分支命名

建议：

```text
agent/<role>/<issue-id>-short-title
```

示例：

```text
agent/devops/LC-0001-repo-bootstrap
agent/backend/LC-0101-initial-schema
agent/mcp/LC-0301-tool-schema
```

## 7. Commit Message

建议格式：

```text
<emoji> <type>: <中文简短描述>
```

示例：

```text
✨ FEAT: 初始化 Cloud MCP 服务骨架
📝 DOCS: 添加 v0.1 架构冻结文档
🔨 BUILD: 配置 pnpm workspace
```

## 8. AI Agent 合并前检查

每个 PR 合并前至少检查：

```text
是否超出 Issue 范围
是否违反架构冻结
是否缺少测试或说明
是否更新相关文档
是否新增未说明依赖
是否影响 audit / trash / import / asset 边界
```
