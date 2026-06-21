# 06. 数据模型设计

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
