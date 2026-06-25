# 53. Local Core Bridge 地基设计

## 背景

`docs/07-sync-and-offline.md`、`docs/08-mcp-design.md`、`docs/10-client-app.md`、`docs/19-local-mcp-desktop.md` 已经给出关键约束：

```text
Flutter Desktop -> Local Core Bridge -> PowerSync SQLite
Local MCP        -> Local Core Bridge -> PowerSync SQLite
```

Local MCP 不能直接写 SQLite，也不能另起一套业务逻辑。Flutter Desktop 后续进入本地优先模式时，也不应绕过同一层本地业务边界。

因此，在真正实现 Windows Local MCP 之前，需要先定义 Local Core Bridge。

## 定位

Local Core Bridge 是 Lifly 桌面本地能力的业务入口层。

它负责把上层调用转换成统一本地业务写入：

```text
Flutter Desktop 手动操作
Local MCP tool 调用
后续离线 AI 调用
后续导入/批处理本地写入
```

Local Core Bridge 不负责 AI 推理，不负责云端 API，不负责对象存储授权，也不直接承担 PowerSync 协议本身。

## 非目标

第一阶段不做：

```text
真实 PowerSync SQLite 写入
完整冲突解决
附件二进制上传/下载
系统托盘常驻进程
HTTP localhost server
Hermes 自动配置
```

第一阶段只定义边界和可测试 fake 实现，避免过早把 Local MCP 写成临时脚本。

## 上游调用方

### Flutter Desktop

未来本地优先模式下，Flutter Desktop 应通过 Local Core Bridge 进行：

```text
memo create/update/delete/search
ledger create/update/delete/search/summary
task create/update/delete/list/complete
asset metadata register
capture parse/commit/undo
```

当前 Flutter 仍是 API 模式。本地优先模式后续单独切换。

### Local MCP

Local MCP 是 stdio MCP server。它只负责：

```text
读取 packages/protocol 的 tool schema
接收 tool call
调用 Local Core Bridge
返回 tool result
```

它不直接写数据库。

## 下游实现

### 第一阶段：In-memory Fake

用于：

```text
Local Core Bridge contract test
Local MCP stdio skeleton
Local MCP smoke test
```

Fake 实现只保证行为形态，不承诺持久化。

### 第二阶段：PowerSync SQLite Adapter

用于：

```text
真实离线创建
重启后数据不丢
联网后同步云端
```

该阶段必须写：

```text
主业务表
audit_logs
revision / updated_at
trash 状态
```

## 与 Cloud MCP 的关系

Cloud MCP 和 Local MCP 必须共享工具 schema。

schema source of truth 仍是：

```text
packages/protocol/src/mcp/tool-schemas.ts
```

Local Core Bridge 可以定义自己的 TypeScript 接口，但其输入输出必须能映射到 MCP v0.1 schema。

禁止 Local MCP 私自增加 tool。新增 tool 必须先进入：

```text
packages/protocol
文档
contract tests
Cloud MCP / Local MCP smoke
```

## 第一阶段接口范围

Local Core Bridge v0.1 先覆盖当前 MCP v0.1 主链路：

```text
health
memo_create
memo_search
expense_create
expense_search
expense_summary
task_create
task_list
task_complete
asset_register_external_url
capture_parse
capture_commit
capture_undo
```

暂缓：

```text
asset_create_upload_url
```

原因：本地离线时无法保证云端对象存储上传 URL 可用。第一阶段可以先返回 unsupported 或 pending。

## 写入要求

真实 adapter 阶段，所有写入必须满足：

```text
不直接物理删除
写 audit log
保留 actor_type / source_channel / tool_name
更新 revision
使用统一 entity id
返回可追踪结果
```

Fake adapter 阶段需要保留这些字段的接口位置，即使不真正持久化。

## 建议目录

```text
packages/local-core/
  src/
    index.ts
    bridge.ts
    fake-local-core.ts
    types.ts
  test/
    local-core.test.ts
  package.json
  tsconfig.json

services/local-mcp/
  src/
    index.ts
    server.ts
    tool-handlers.ts
  test/
    local-mcp.test.ts
  package.json
  tsconfig.json
```

使用 `services/local-mcp` 而不是 `apps/local_mcp`，因为当前 `pnpm-workspace.yaml` 已经预留：

```text
services/local-mcp
```

## 六个提交计划

### Commit 1：Local Core Bridge 文档

产物：

```text
docs/53-local-core-bridge-foundation.md
```

### Commit 2：MCP schema 实现审计

产物：

```text
docs/54-mcp-schema-implementation-audit.md
```

### Commit 3：packages/local-core contract + fake

产物：

```text
packages/local-core
```

### Commit 4：services/local-mcp stdio skeleton

产物：

```text
services/local-mcp
```

### Commit 5：Local MCP smoke

产物：

```text
scripts/smoke-local-mcp-v0.1.sh
```

### Commit 6：Flutter Local MCP diagnostics placeholder

产物：

```text
apps/client_flutter/lib/features/settings/...
docs/55-flutter-local-mcp-diagnostics-placeholder.md
```

## 验收策略

每个代码切片至少满足：

```text
pnpm --filter <package> test
pnpm --filter <package> typecheck
cd apps/client_flutter && flutter analyze . && flutter test
bash scripts/smoke-mcp-v0.1.sh
```

其中 Flutter 和后端 smoke 不一定每个纯文档 commit 都跑，但最终第六个 commit 前必须完整通过。
