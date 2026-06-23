# 28. Lifly AI-Native Issues Backlog

本文档是 Lifly v0.1 的 Issue 种子清单。每个 Issue 都应包含目标、范围、禁止事项、验收标准和相关文档。

## M0 Issues

### LC-0000 Rename and align project as Lifly

目标：统一仓库中旧命名为 Lifly / lifly。

验收：

- README 标题为 Lifly
- 根 package 名称为 lifly
- Docker 服务命名为 lifly
- 文档统一使用 Lifly

### LC-0001 Add v0.1 architecture freeze docs

目标：补齐 Lifly v0.1 架构冻结文档。

验收：

- docs/26-v0.1-architecture-freeze.md 存在
- 文档明确 MVP 范围和禁止事项
- 文档明确 MCP、同步、附件、删除边界

### LC-0002 Establish AI execution governance

目标：补齐 AI agent 执行协议、角色边界、PR Review 规则。

验收：

- docs/29-ai-role-boundaries.md 存在
- docs/31-agent-task-protocol.md 存在
- docs/32-pr-review-protocol.md 存在

## M1 Issues

- LC-0101 Local memo CRUD
- LC-0102 Local expense CRUD
- LC-0103 Local task CRUD
- LC-0104 Local asset metadata

## M2 Issues

- LC-0201 PowerSync integration spike
- LC-0202 Audit log write path
- LC-0203 Trash state machine

## M3 Issues

- LC-0301 MCP tool schema package
- LC-0302 memo_create / expense_create / task_create
- LC-0303 capture_parse / capture_commit / capture_undo

## M4 Issues

- LC-0401 Asset upload URL flow
- LC-0402 Generic CSV import preview
- LC-0403 Import batch commit and rollback
