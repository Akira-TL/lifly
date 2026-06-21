# 33. GitHub / GitLab 项目设置

## 1. Milestones

创建：

```text
M0 Repo Bootstrap & Technical Spikes
M1 Local Data MVP
M2 Cloud Sync MVP
M3 Cloud MCP MVP
M4 Assets & Import MVP
M5 Windows Local MCP
```

## 2. GitHub Project 字段

```text
Status: Ready / In Progress / Review / Done / Blocked
Agent: Architect / Client / Backend / MCP / Sync / Asset / Import / QA / DevOps / Docs
Area
Priority
Milestone
```

## 3. Branch Protection

保护 main：

```text
禁止直接 push main
必须通过 PR
CI 通过才能 merge
禁止 force push
```

## 4. Issue 创建原则

Issue 必须自包含，不依赖聊天历史。必须写清 Goal、Context、Scope、Allowed files、Forbidden changes、Acceptance criteria、Validation、Related docs。

## 5. 分支命名

```text
agent/<role>/<issue-id>-short-title
```

示例：

```text
agent/devops/LC-0001-repo-bootstrap
agent/backend/LC-0101-initial-schema
agent/mcp/LC-0301-tool-schema
```
