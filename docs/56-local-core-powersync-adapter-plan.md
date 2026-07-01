# 56. Local Core Bridge → PowerSync Adapter 规划

## 背景

上一阶段完成了：

```text
docs/53-local-core-bridge-foundation.md
docs/54-mcp-schema-implementation-audit.md
packages/local-core fake bridge
services/local-mcp stdio skeleton
scripts/smoke-local-mcp-v0.1.sh
Flutter Local MCP 状态占位
```

当前 Local MCP 已能通过 fake Local Core 跑通 v0.1 主链路，但还没有真实本地持久化。下一阶段目标是为 Local Core Bridge 接入真实本地数据层做准备。

## 当前关键发现

### 1. Flutter PowerSync schema 仍是早期最小草案

当前文件：

```text
apps/client_flutter/lib/data/powersync/sync_service.dart
```

目前只定义了：

```text
memos
tasks
ledger_transactions
```

且字段不完整。例如：

```text
memos 缺少 tags / source / source_capture_id / deleted_at / revision
ledger_transactions 缺少 account_id / category_id / source / source_capture_id / import_batch_id / confidence / deleted_at / revision
tasks 缺少 source / source_capture_id / deleted_at / revision
```

同时还缺少：

```text
assets
memo_asset_refs
audit_logs
mcp_undo_actions
tombstones
ledger_accounts
ledger_categories
```

这意味着不能马上把 Local Core fake 替换成 PowerSync 写入，否则 audit/revision/trash/undo 都无法保证。

### 2. 后端数据模型比 Flutter 本地 schema 完整

后端 source of truth 当前主要在：

```text
services/api/app/db/models.py
docs/06-data-model.md
```

后端已具备：

```text
RevisionMixin
SoftDeleteMixin
AuditLog
McpUndoAction
Tombstone
Asset / MemoAssetRef
LedgerAccount / LedgerCategory
```

Local Core adapter 应向后端模型靠齐，而不是向当前 Flutter 最小 schema 靠齐。

### 3. Node Local MCP 不能直接拥有 Flutter PowerSync SQLite

当前 Local MCP skeleton 是 TypeScript/Node：

```text
services/local-mcp
```

当前 Flutter PowerSync 是 Dart：

```text
apps/client_flutter/lib/data/powersync/sync_service.dart
```

如果 Node Local MCP 直接写 Flutter PowerSync SQLite 文件，会产生问题：

```text
多进程直接写同一 SQLite
绕过 Dart PowerSync client 的 CRUD tracking
绕过 Flutter 本地 repository / sync 状态
难以保证 audit/revision/trash 一致
```

这与 `docs/07-sync-and-offline.md` 中的禁止事项冲突。

因此，真实方案需要一个“单一数据库写入所有者”。

## 建议架构决策

### 决策：Flutter Desktop / Dart Local Core 拥有 PowerSync 连接

真实 PowerSync adapter 应优先在 Flutter/Dart 侧实现。

推荐长期结构：

```text
Hermes / Local Agent
        ↓ stdio
TypeScript Local MCP shim
        ↓ local bridge transport
Dart Local Core Bridge inside Flutter Desktop
        ↓
PowerSyncDatabase
        ↓
PowerSync uploadData
        ↓
Cloud API / PostgreSQL
```

含义：

```text
TypeScript Local MCP 负责 MCP 协议与工具 schema
Dart Local Core Bridge 负责真实本地数据写入
PowerSyncDatabase 只由 Flutter/Dart 进程持有
```

第一阶段仍保留 TypeScript fake local-core，用于协议和 smoke；真实本地持久化不在 Node 里直接写 SQLite。

## 下一阶段切片计划

### Slice 1：PowerSync schema 对齐文档与字段清单

目标：补齐本地 schema 对齐计划。

产物：

```text
docs/57-powersync-schema-alignment.md
```

内容：

```text
后端模型字段
当前 Flutter PowerSync 字段
缺失字段
MVP 必须补齐字段
后续字段
```

### Slice 2：Flutter PowerSync schema 扩展

目标：先让 Flutter 本地 schema 能承载真实本地写入所需字段。

修改：

```text
apps/client_flutter/lib/data/powersync/sync_service.dart
```

优先补齐：

```text
memos.tags
memos.source
memos.source_capture_id
memos.deleted_at
memos.revision

tasks.source
tasks.source_capture_id
tasks.deleted_at
tasks.revision

ledger_transactions.account_id
ledger_transactions.category_id
ledger_transactions.source
ledger_transactions.source_capture_id
ledger_transactions.import_batch_id
ledger_transactions.confidence
ledger_transactions.deleted_at
ledger_transactions.revision
```

新增表：

```text
audit_logs
mcp_undo_actions
tombstones
assets
memo_asset_refs
```

### Slice 3：Dart Local Core Bridge 接口

目标：在 Flutter 侧新增本地核心桥接口，不接 UI。

建议目录：

```text
apps/client_flutter/lib/data/local_core/
  local_core_bridge.dart
  local_core_context.dart
  local_core_models.dart
```

先定义：

```text
createMemo
searchMemos
createExpense
searchExpenses
summarizeExpenses
createTask
listTasks
completeTask
registerExternalAsset
captureParse
captureCommit
captureUndo
health
```

### Slice 4：Dart Local Core fake + tests

目标：Flutter/Dart 侧也有 fake local core，和 TypeScript fake 行为对齐。

用途：

```text
Flutter 本地模式 UI 测试
未来 Local MCP bridge transport 测试
```

### Slice 5：Dart PowerSyncLocalCoreBridge 最小写入

目标：只实现真实本地写入最小闭环：

```text
memo_create
memo_search
task_create
task_list
task_complete
```

必须写：

```text
业务表
audit_logs
revision
source/source_channel/tool_name
```

暂缓：

```text
expense
asset
capture undo
完整 uploadData
```

### Slice 6：Flutter 设置页本地能力 smoke 占位升级

目标：设置页能运行 Dart Local Core fake smoke 或 PowerSync local smoke。

不启动 TypeScript Local MCP，不生成 Hermes 配置。

## 当前这一轮先做什么

本轮先完成：

```text
1. 本规划文档
2. PowerSync schema 对齐文档 docs/57
3. Flutter PowerSync schema 扩展第一版
```

不做：

```text
真实本地写入
Flutter 调 Local MCP
Node 直接写 SQLite
PowerSync uploadData 实现
```

## 验收

每个代码切片需要：

```bash
cd apps/client_flutter
flutter analyze .
flutter test
```

涉及 Local MCP 仍需：

```bash
pnpm --filter @lifly/local-core typecheck
pnpm --filter @lifly/local-mcp typecheck
bash scripts/smoke-local-mcp-v0.1.sh
```

最终回归：

```bash
bash scripts/smoke-mcp-v0.1.sh
```
