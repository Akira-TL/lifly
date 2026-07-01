# 28. AI-Native Issues Backlog

## Label 规范

```text
type:spike type:feature type:bug type:docs type:infra
area:repo area:client area:backend area:mcp area:sync area:asset area:ledger area:memo area:task area:import area:security
agent:architect agent:client agent:backend agent:mcp agent:qa agent:devops agent:docs
priority:p0 priority:p1 priority:p2
status:ready status:blocked needs-architecture-decision
```

## M0 Issues

### LC-0001 Repo bootstrap

Labels: `type:infra, area:repo, agent:devops, priority:p0`

目标：创建 monorepo 基础结构，加入 docs、pnpm workspace、turbo、Flutter/FastAPI/MCP 服务目录。

验收：pnpm install 成功；docker compose config 成功；docs/ 存在并包含 v0.1 架构冻结文档。

### LC-0002 Add docs v0.1 into repository

Labels: `type:docs, agent:docs, priority:p0`

目标：将开发文档包放入 docs/，并在 README 中链接关键文档。

验收：docs/00-decision-record.md 存在；docs/26-v0.1-architecture-freeze.md 存在；README.md 有 Docs Index。

### LC-0003 FastAPI skeleton

Labels: `type:infra, area:backend, agent:backend, priority:p0`

目标：初始化 services/api，提供 health check。

验收：uv sync 成功；GET /health 返回 ok。

### LC-0004 Cloud MCP skeleton

Labels: `type:infra, area:mcp, agent:mcp, priority:p0`

目标：初始化 services/cloud-mcp，提供基础 MCP server 和 tool list。

验收：pnpm --filter @lifly/cloud-mcp dev 可启动；能列出 ping tool。

### LC-0005 Flutter client skeleton

Labels: `type:infra, area:client, agent:client, priority:p0`

目标：初始化 apps/client_flutter，支持 Windows 和 Android 构建。

验收：flutter analyze 通过；flutter run -d windows 可运行；Android emulator 可运行。

### LC-0006 Docker Compose local infra

Labels: `type:infra, area:devops, agent:devops, priority:p0`

目标：提供 PostgreSQL、Redis、MinIO、PowerSync 的本地开发配置。

验收：docker compose up -d 成功；PostgreSQL、Redis、MinIO 可连接。

## M1 Issues

### LC-0101 Define initial database schema

目标：实现 memos、ledger_transactions、tasks、assets、audit_logs 的初始 migration。

验收：migration 可执行；所有表有 user_id/status/revision/created_at/updated_at。

### LC-0102 Local memo CRUD

目标：客户端实现本地 memo 创建、编辑、列表。

验收：无网络可创建 memo；支持 memo/journal/clip/doc 类型。

### LC-0103 Local expense CRUD

目标：客户端实现本地账单创建、编辑、列表。

验收：无网络可创建账单；金额、分类、商户、时间可编辑。

### LC-0104 Local task CRUD

目标：客户端实现本地任务创建、完成、列表。

验收：无网络可创建任务；任务可标记完成；remind_at 字段可保存。
