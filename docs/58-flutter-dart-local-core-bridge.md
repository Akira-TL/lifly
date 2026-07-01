# 58. Flutter Dart Local Core Bridge 接口与 Fake

## 背景

`docs/56-local-core-powersync-adapter-plan.md` 明确：真实 PowerSync 数据库连接应由 Flutter/Dart 侧拥有，TypeScript Local MCP 不应直接写 Flutter PowerSync SQLite 文件。

因此需要在 Flutter/Dart 侧建立 Local Core Bridge 接口，为后续 PowerSyncLocalCoreBridge 做准备。

## 新增文件

```text
apps/client_flutter/lib/data/local_core/local_core_context.dart
apps/client_flutter/lib/data/local_core/local_core_models.dart
apps/client_flutter/lib/data/local_core/local_core_bridge.dart
apps/client_flutter/lib/data/local_core/fake_local_core_bridge.dart
```

## 接口范围

Dart Local Core Bridge 当前对齐 MCP v0.1 主链路：

```text
health
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
```

## Fake 实现

`FakeLocalCoreBridge` 使用内存数据结构实现最小行为，目的不是持久化，而是：

```text
验证 Dart 侧接口语义
为 Flutter 本地模式 UI 测试提供替身
为后续 PowerSyncLocalCoreBridge 提供行为参照
```

当前 fake 支持：

```text
memo create/search
expense create/search/summary
task create/list/complete
asset external register
capture parse/commit/undo
```

## 测试

新增：

```text
apps/client_flutter/test/local_core_test.dart
```

覆盖：

```text
health
memo create/search
expense create/search/summary
task create/list/complete
capture parse/commit/undo
```

## 非目标

本切片不做：

```text
真实 PowerSync 写入
Flutter 页面切换到 Local Core
Local MCP 启动 Flutter 进程
跨进程 bridge transport
uploadData 同步云端
```

## 下一步

下一步可以新增：

```text
apps/client_flutter/lib/data/local_core/powersync_local_core_bridge.dart
```

并先只实现：

```text
health
createMemo
searchMemos
createTask
listTasks
completeTask
```

真实 adapter 必须同时写：

```text
业务表
audit_logs
revision
source/source_channel/tool_name
```
