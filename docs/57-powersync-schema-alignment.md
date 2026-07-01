# 57. Flutter PowerSync Schema 对齐清单

## 背景

当前 Flutter PowerSync schema 位于：

```text
apps/client_flutter/lib/data/powersync/sync_service.dart
```

它仍是早期最小草案，只覆盖：

```text
memos
tasks
ledger_transactions
```

但 Local Core Bridge 真实写入需要满足：

```text
业务表写入
audit_logs 写入
revision 增加
删除状态机
MCP undo 可追踪
附件 metadata 可同步
```

因此需要先扩展 Flutter PowerSync schema。

## 对齐来源

本清单参考：

```text
docs/06-data-model.md
services/api/app/db/models.py
services/api/app/modules/memos/service.py
services/api/app/modules/ledger/service.py
services/api/app/modules/tasks/service.py
```

## 当前缺口总览

| 表 | 当前 Flutter schema | 后端 / 文档要求 | 结论 |
| --- | --- | --- | --- |
| memos | partial | full core fields | 需补齐 |
| tasks | partial | full core fields | 需补齐 |
| ledger_transactions | partial | full core fields | 需补齐 |
| assets | missing | required for metadata sync | 需新增 |
| memo_asset_refs | missing | required for memo asset binding | 需新增 |
| audit_logs | missing | required for all writes | 需新增 |
| mcp_undo_actions | missing | required for MCP undo | 需新增 |
| tombstones | missing | required for purge sync | 需新增 |
| ledger_accounts | missing | later category/account UX | 可先新增 schema |
| ledger_categories | missing | later category UX | 可先新增 schema |

## MVP 必须补齐字段

### memos

当前已有：

```text
id
user_id
type
title
content_markdown
mood
status
created_at
updated_at
```

需补齐：

```text
tags
source_capture_id
source
deleted_at
revision
```

### tasks

当前已有：

```text
id
user_id
title
description
due_at
remind_at
priority
task_status
status
created_at
updated_at
completed_at
```

需补齐：

```text
source_capture_id
source
deleted_at
revision
```

### ledger_transactions

当前已有：

```text
id
user_id
direction
amount
currency
merchant
note
occurred_at
status
created_at
updated_at
```

需补齐：

```text
account_id
category_id
source
source_capture_id
import_batch_id
confidence
deleted_at
revision
```

## MVP 必须新增表

### audit_logs

用于所有本地写入审计。

字段：

```text
id
user_id
actor_type
actor_id
action
entity_type
entity_id
before_snapshot
after_snapshot
source_channel
source_text
tool_name
request_id
created_at
```

### mcp_undo_actions

用于 capture_commit / capture_undo。

字段：

```text
id
user_id
undo_token
entity_type
entity_id
action
status
expires_at
used_at
created_at
```

### tombstones

用于 purge 同步。

字段：

```text
id
user_id
entity_type
entity_id
purged_at
last_revision
```

### assets

用于附件 metadata 同步。

字段：

```text
id
user_id
kind
asset_type
filename
mime_type
size_bytes
sha256
storage_provider
storage_key
external_url
external_provider
visibility
sync_status
status
created_at
updated_at
```

### memo_asset_refs

用于 memo 与 asset 的绑定。

字段：

```text
id
memo_id
asset_id
ref_type
position_hint
created_at
```

## 建议同步但暂不使用的表

### ledger_accounts

字段：

```text
id
user_id
name
type
currency
is_default
status
created_at
updated_at
```

### ledger_categories

字段：

```text
id
user_id
name
parent_id
type
icon
color
sort_order
status
created_at
updated_at
```

## 不在本轮处理

以下表暂不进入 Flutter PowerSync schema：

```text
ledger_entries
reminders
calendar_events
import_batches
import_rows
users
api_tokens
```

原因：当前 Local Core MVP 不会直接写这些表。后续导入、提醒、日历、账号系统进入对应阶段时再补。

## 本轮 schema 扩展原则

只改 schema，不改：

```text
PowerSync uploadData
客户端 repository 读写模式
Flutter 页面行为
Local MCP 启动方式
```

本轮只是让本地数据库具备承载真实 Local Core 写入的结构条件。

## 后续验收

```bash
cd apps/client_flutter
flutter analyze .
flutter test
```

如果 Flutter PowerSync schema API 因字段类型不匹配报错，以 Flutter analyzer 为准。
