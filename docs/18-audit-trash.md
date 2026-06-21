# 18. 审计、回收站与删除策略

## 1. 目标

所有关键操作必须可追踪、可解释、可撤销。

特别是 AI 操作必须严格审计，避免 AI 擅自修改或删除用户数据后无法恢复。

## 2. 审计范围

必须写 audit log 的操作：

- create；
- update；
- delete；
- restore；
- purge；
- import；
- export；
- batch_commit；
- batch_rollback；
- asset_upload；
- asset_delete。

## 3. AuditLog 字段

```text
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

## 4. Actor 类型

```text
user
ai
system
import
```

## 5. 删除状态机

核心状态：

```text
active
archived
ai_trashed
user_trashed
purged
```

## 6. AI 删除

AI 删除只能：

```text
active → ai_trashed
```

AI 删除后：

- 不清除内容；
- 不物理删除；
- 用户可恢复；
- 用户可确认删除。

## 7. 用户删除

用户删除：

```text
active → user_trashed
```

保留 30 天。30 天内可恢复。

## 8. 清理

超过 30 天后：

```text
user_trashed → purged
```

purged 需要：

- 清除正文；
- 清除金额/备注等敏感内容；
- 断开附件引用；
- 保留 tombstone；
- 写 audit log。

## 9. 附件删除

附件删除要检查引用关系。

```text
如果 asset 仍被 memo 引用 → 不删除
如果 asset 无引用且超过清理期 → 删除对象存储文件
```

## 10. 撤销

capture_commit 返回 undo_token。撤销操作本质是反向操作，不是直接删除 audit log。

例如：

- 新建账单撤销 → 账单进入 ai_trashed 或 user_trashed；
- 修改撤销 → 恢复 before_snapshot；
- 批量导入撤销 → 批次回滚。

## 11. 审计查询

客户端需要提供：

- 最近 AI 操作；
- 最近导入；
- 回收站；
- 某条记录的修改历史，后续实现。

MVP 至少提供：

- AI 回收站；
- 普通回收站；
- 最近操作记录。
