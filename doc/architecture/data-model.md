# 数据模型设计

> 本文档是逻辑模型草案，不是最终迁移脚本。实际建表需结合 PowerSync、PostgreSQL、客户端 SQLite 和 ORM 约束调整。

## 1. 通用字段

所有核心表建议包含：

```sql
id UUID PRIMARY KEY
user_id UUID NOT NULL
created_at TIMESTAMPTZ NOT NULL
updated_at TIMESTAMPTZ NOT NULL
deleted_at TIMESTAMPTZ NULL
status TEXT NOT NULL
revision BIGINT NOT NULL
source TEXT NULL
```

## 2. capture_items

```sql
CREATE TABLE capture_items (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  source_channel TEXT NOT NULL,
  source_message_id TEXT,
  raw_text TEXT,
  raw_payload JSONB,
  parsed_result JSONB,
  parsed_status TEXT NOT NULL,
  committed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL
);
```

## 3. memos

```sql
CREATE TABLE memos (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  type TEXT NOT NULL, -- memo / journal / clip / doc
  title TEXT,
  content_markdown TEXT NOT NULL,
  tags TEXT[],
  mood TEXT,
  source_capture_id UUID,
  status TEXT NOT NULL, -- active / archived / ai_trashed / user_trashed / purged
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  revision BIGINT NOT NULL
);
```

## 4. assets

```sql
CREATE TABLE assets (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  kind TEXT NOT NULL, -- internal / external
  asset_type TEXT NOT NULL, -- image / pdf / ppt / mindmap / file / link
  filename TEXT,
  mime_type TEXT,
  size_bytes BIGINT,
  sha256 TEXT,
  storage_provider TEXT,
  storage_key TEXT,
  external_url TEXT,
  external_provider TEXT,
  visibility TEXT NOT NULL,
  sync_status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL
);
```

## 5. memo_asset_refs

```sql
CREATE TABLE memo_asset_refs (
  id UUID PRIMARY KEY,
  memo_id UUID NOT NULL,
  asset_id UUID NOT NULL,
  ref_type TEXT NOT NULL,
  position_hint TEXT,
  created_at TIMESTAMPTZ NOT NULL
);
```

## 6. ledger_accounts

```sql
CREATE TABLE ledger_accounts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL, -- cash / wallet / bank / credit / other
  currency TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
```

## 7. ledger_categories

```sql
CREATE TABLE ledger_categories (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  parent_id UUID,
  type TEXT NOT NULL, -- expense / income / transfer
  icon TEXT,
  color TEXT,
  sort_order INTEGER,
  status TEXT NOT NULL
);
```

## 8. ledger_transactions

```sql
CREATE TABLE ledger_transactions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  account_id UUID,
  category_id UUID,
  direction TEXT NOT NULL, -- expense / income / transfer
  amount NUMERIC(18, 2) NOT NULL,
  currency TEXT NOT NULL,
  merchant TEXT,
  note TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  source TEXT NOT NULL, -- manual / ai / import
  source_capture_id UUID,
  import_batch_id UUID,
  confidence NUMERIC(5, 4),
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  revision BIGINT NOT NULL
);
```

## 9. ledger_entries 预留

```sql
CREATE TABLE ledger_entries (
  id UUID PRIMARY KEY,
  transaction_id UUID NOT NULL,
  account_id UUID NOT NULL,
  entry_type TEXT NOT NULL, -- debit / credit
  amount NUMERIC(18, 2) NOT NULL,
  currency TEXT NOT NULL
);
```

MVP 可以暂不使用 ledger_entries，但保留未来升级空间。

## 10. tasks

```sql
CREATE TABLE tasks (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_at TIMESTAMPTZ,
  remind_at TIMESTAMPTZ,
  priority TEXT,
  task_status TEXT NOT NULL, -- todo / doing / done / cancelled
  source_capture_id UUID,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  revision BIGINT NOT NULL
);
```

## 11. reminders

```sql
CREATE TABLE reminders (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  target_type TEXT NOT NULL,
  target_id UUID NOT NULL,
  remind_at TIMESTAMPTZ NOT NULL,
  channel TEXT NOT NULL, -- app / push / email / bot
  reminder_status TEXT NOT NULL, -- pending / sent / cancelled / failed
  created_at TIMESTAMPTZ NOT NULL
);
```

## 12. calendar_events 预留

```sql
CREATE TABLE calendar_events (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  location TEXT,
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ,
  all_day BOOLEAN NOT NULL DEFAULT false,
  timezone TEXT,
  rrule TEXT,
  external_uid TEXT,
  source_provider TEXT,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  revision BIGINT NOT NULL
);
```

## 13. import_batches

```sql
CREATE TABLE import_batches (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  source_provider TEXT NOT NULL, -- generic_csv / alipay / wechat
  filename TEXT,
  file_hash TEXT,
  status TEXT NOT NULL, -- preview / committed / rolled_back / failed
  total_rows INTEGER,
  valid_rows INTEGER,
  duplicate_rows INTEGER,
  created_at TIMESTAMPTZ NOT NULL,
  committed_at TIMESTAMPTZ,
  rolled_back_at TIMESTAMPTZ
);
```

## 14. import_rows

```sql
CREATE TABLE import_rows (
  id UUID PRIMARY KEY,
  batch_id UUID NOT NULL,
  row_index INTEGER NOT NULL,
  raw_data JSONB NOT NULL,
  parsed_data JSONB,
  status TEXT NOT NULL,
  transaction_id UUID,
  error_message TEXT
);
```

## 15. audit_logs

```sql
CREATE TABLE audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  actor_type TEXT NOT NULL, -- user / ai / system / import
  actor_id TEXT,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  before_snapshot JSONB,
  after_snapshot JSONB,
  source_channel TEXT,
  source_text TEXT,
  tool_name TEXT,
  request_id TEXT,
  created_at TIMESTAMPTZ NOT NULL
);
```

## 16. tombstones

```sql
CREATE TABLE tombstones (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID NOT NULL,
  purged_at TIMESTAMPTZ NOT NULL,
  last_revision BIGINT NOT NULL
);
```

## 17. 现状与扩展模型边界

本文档同时记录已实现模型和下一阶段需要稳定下来的长期模型。实际迁移脚本必须以代码和 migration 为准。

当前已实现核心表覆盖：

```text
memos
assets
memo_asset_refs
ledger_accounts
ledger_categories
ledger_transactions
ledger_entries
tasks
reminders
calendar_events
import_batches
import_rows
audit_logs
mcp_undo_actions
```

下一阶段产品地基需要补充的模型如下，未实现前客户端只能兼容降级，不能伪造对应产品能力。

## 18. memo_classifications

用于支撑备忘 AI 自动分类、分类置信度、AI 建议状态和用户确认状态。

```sql
CREATE TABLE memo_classifications (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  memo_id UUID NOT NULL,
  label TEXT NOT NULL,
  label_type TEXT NOT NULL, -- tag / type / topic / intent
  source TEXT NOT NULL, -- ai / user / rule / import
  confidence NUMERIC(5, 4),
  status TEXT NOT NULL, -- suggested / confirmed / rejected
  model_name TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  confirmed_at TIMESTAMPTZ
);
```

`memos.tags` 可以继续作为轻量冗余字段，但长期分类事实以 `memo_classifications` 为准。

## 19. tag_metadata

用于支撑标签颜色、图标、排序、统计和多模块标签复用。

```sql
CREATE TABLE tag_metadata (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  name TEXT NOT NULL,
  kind TEXT NOT NULL, -- memo / ledger / task / global
  color_token TEXT,
  icon_token TEXT,
  sort_order INTEGER,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
```

## 20. ledger_budgets

用于支撑预算进度、分类预算、预算阈值提醒和首页财务概览。

```sql
CREATE TABLE ledger_budgets (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  period_type TEXT NOT NULL, -- 当前实现固定 month
  period_key TEXT NOT NULL,
  category_id UUID,
  amount NUMERIC(18, 2) NOT NULL,
  currency TEXT NOT NULL,
  alert_threshold NUMERIC(5, 4),
  status TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
```

`category_id IS NULL` 表示总预算；`category_id IS NOT NULL` 表示分类预算。业务层保证 `(user_id, period_type, period_key, category_id)` 在 active 状态下唯一；`revision` 用于 PowerSync 陈旧写入判定。现有数据库通过 additive schema compatibility 补齐 `revision`，正式迁移框架落地后应迁入版本化 migration。

## 21. task_reminder_strategies

用于支撑 AI 提醒建议、任务预警、提前准备窗口和用户确认状态。

```sql
CREATE TABLE task_reminder_strategies (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  task_id UUID NOT NULL,
  warning_level TEXT NOT NULL, -- critical / warning / normal
  warning_reason TEXT,
  preparation_window_days INTEGER,
  suggested_start_at TIMESTAMPTZ,
  ai_suggested_remind_at TIMESTAMPTZ,
  confidence NUMERIC(5, 4),
  status TEXT NOT NULL, -- suggested / confirmed / dismissed / expired
  created_by TEXT NOT NULL, -- ai / user / rule
  created_at TIMESTAMPTZ NOT NULL,
  confirmed_at TIMESTAMPTZ
);
```

策略不是提醒派发本身。策略确认后才写入或更新 `Task.remind_at` 和 `Reminder`。

## 22. mcp_capture_sessions / mcp_capture_turns

用于把当前 parse / commit / undo 能力封装成聊天式 AI Capture 体验。当前命名沿用 MCP capture 链路，后续如果抽成非 MCP Capture API，可以在兼容层上再提供 `capture_sessions` 视图或别名。

```sql
CREATE TABLE mcp_capture_sessions (
  capture_id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  original_text TEXT NOT NULL,
  timezone TEXT NOT NULL,
  locale TEXT NOT NULL,
  actions JSONB NOT NULL,
  requires_confirmation BOOLEAN NOT NULL,
  committed BOOLEAN NOT NULL,
  session_status TEXT NOT NULL, -- parsed / committed / failed / dismissed / expired
  source_channel TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  committed_at TIMESTAMPTZ,
  dismissed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE mcp_capture_turns (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL,
  capture_id UUID NOT NULL,
  turn_index INTEGER NOT NULL,
  role TEXT NOT NULL, -- user / assistant / system
  text TEXT,
  actions JSONB,
  selected_action_indexes JSONB,
  result_entities JSONB,
  turn_status TEXT NOT NULL, -- parsed / committed / failed / undone / partial
  source_channel TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);
```

本地 PowerSync 也保存 `mcp_capture_sessions` 和 `mcp_capture_turns`。本地 commit 创建 memo / task / ledger_transaction 时写入 `source_capture_id`，undo 通过 `mcp_undo_actions` 将创建实体转为 `ai_trashed` 并追加 undo turn。

附件和语音不直接塞进文本字段。附件只传 `asset_ids` 引用边界；语音应先形成音频 Asset，经 STT 生成文本后进入 capture turn。

## 23. 本地 read model 边界

首页概览、预算统计、分类占比、任务预警、标签统计和最近混合内容流原则上不需要单独持久化为正式业务表，应优先由 Local Core 基于本地 PowerSync SQLite 计算。

本地 read model 输出必须和云端同构 API 保持字段一致：

```text
schema_version
generated_at
user_timezone
source_mode: local / api / fallback
```

可本地计算的 read model 包括：

```text
HomeOverview
LedgerOverview
LedgerCategorySummary
LedgerInsight
MemoTagSummary
TaskWarningGroup
RecentActivityFeed
```

只有在存在性能问题、离线启动耗时问题或需要历史快照时，才考虑新增缓存表。缓存表不是事实来源，可以随时清空重建。
