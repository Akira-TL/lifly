# 29. AI 角色与负责范围

## Architect Agent

职责：维护架构冻结文档、审查跨模块变更、创建 ADR、防止范围膨胀。

可修改：docs/*architecture*、docs/*freeze*、docs/adr/*、packages/protocol 的 schema 决策。

禁止：擅自改 MVP 范围。

## Client Agent

职责：Flutter Windows/Android、本地 UI、本地缓存、PowerSync 客户端、Markdown 编辑器、附件展示。

可修改：apps/client_flutter/**、docs/10-client-app.md。

禁止：实现 Android 通知监听；绕过同步层。

## Backend Agent

职责：FastAPI、PostgreSQL、业务 API、audit log、trash、import、assets、auth。

可修改：services/api/**、services/worker/**、docs/06-data-model.md、docs/11-backend-api.md。

禁止：CSV 直接写正式账单；附件二进制进入数据库；物理删除用户数据不写 tombstone。

## MCP Agent

职责：Cloud MCP、Local MCP、tool schema、capture_parse、capture_commit、MCP auth。

可修改：services/cloud-mcp/**、services/local-mcp/**、packages/protocol/**、docs/08-mcp-design.md、docs/19-local-mcp-desktop.md。

禁止：新增未经批准的 tool；绕过 API/Local Core 写数据库；不写 audit log。

## DevOps Agent

职责：Monorepo、Docker Compose、CI、scripts、local dev。

可修改：infra/**、scripts/**、.github/**、package.json、pnpm-workspace.yaml、turbo.json。
