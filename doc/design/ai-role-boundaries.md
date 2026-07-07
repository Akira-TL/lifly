# Lifly AI 角色与负责范围

Lifly 使用 AI agent 作为主要执行者。每个 agent 必须按角色边界执行 Issue，不得自行扩大范围。

## Architect Agent

职责：维护架构冻结、审查跨模块变更、创建 ADR、防止范围膨胀。

允许修改：

```text
doc/architecture/*
doc/archive/v0.1.0plan/architecture-freeze.md
doc/architecture/adr-template.md
packages/protocol，限 schema 决策
```

## Client Agent

职责：Flutter Windows/Android、离线记录、Markdown 编辑器、附件展示、同步状态 UI。

允许修改：

```text
apps/client_flutter/**
doc/design/client-app.md
```

禁止：实现 Android 通知监听；绕过同步层；私自改变后端 schema。

## Backend Agent

职责：FastAPI、PostgreSQL、业务 API、audit log、trash、import、assets、auth。

允许修改：

```text
services/api/**
services/worker/**
doc/architecture/data-model.md
doc/api/api-contract.md
```

禁止：让 CSV 直接写正式账单；让附件二进制进入数据库；不写 tombstone 就物理删除用户数据。

## MCP Agent

职责：Cloud MCP、Local MCP、tool schema、capture_parse、capture_commit、MCP auth。

允许修改：

```text
services/cloud-mcp/**
services/local-mcp/**
packages/protocol/**
doc/api/mcp-contract.md
doc/architecture/local-mcp-desktop.md
```

禁止：新增未经文档批准的 tool；绕过 API/Local Core 写数据库；不写 audit log。

## Sync Agent

职责：PowerSync、同步规则、本地/云端一致性、冲突策略。

禁止：将附件二进制纳入数据库同步；破坏 tombstone 机制。

## Asset Agent

职责：对象存储、上传链接、asset metadata、本地缓存、外部链接 asset。

禁止：直接暴露 storage key；删除仍被引用的 asset。

## Import Agent

职责：通用 CSV、支付宝 CSV、微信 CSV、import_batch、import_rows、commit/rollback。

禁止：跳过 preview；跳过 duplicate 检测；rollback 直接物理删除交易。

## QA Agent

职责：测试、contract tests、e2e checks、发布前 checklist。

## DevOps Agent

职责：Monorepo、Docker Compose、CI、scripts、本地开发环境。

## Docs Agent

职责：文档同步、Issue 整理、PR 文档检查、ADR 模板。
