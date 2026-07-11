# 本地优先与同步设计

## 1. 目标

同步设计必须满足：

- Windows/Android 离线可用；
- 离线创建、修改、删除不丢失；
- 恢复网络后自动同步；
- 云端和客户端最终一致；
- 附件 metadata 与二进制文件分离；
- AI、本地手动、导入都能进入同一同步流程；
- 首页概览、预算统计、分类占比、任务预警、标签统计等产品化 read model 必须能基于本地数据计算，不依赖云端实时聚合。

## 2. 同步系统

采用 PowerSync。

客户端读写本地 SQLite，PowerSync 负责将本地变化同步到云端，并将云端变化同步到本地。

产品化聚合能力采用云端同步优先、本地兜底：

```text
PowerSync SQLite
  ↓
Local Core query / read model service
  ↓
Flutter repository
  ↓
UI
```

云端 API 是正常联网状态下的读取入口；Local Core 提供同构 read model，在云端失败、断网或弱网时兜底，不能让首页、预算、分类占比、任务预警等能力被网络卡死。备忘分类建议、标签元数据、任务预警策略和 pending reminders 也必须在 PowerSync 本地库中完整落地。

首页同步状态必须区分观察位置：服务端只能报告 PowerSync 配置是否可用以及服务端可验证的附件同步统计，不能推断具体客户端在线；客户端 Local Core 读取 PowerSync `currentStatus`，报告连接、连接中、下载、上传、最近同步时间和错误。最新导入状态通过同步到本地的 `import_batches` 计算，不保存不可验证的固定占位状态。

PowerSync 运行配置通常按环境管理并可被 Git 忽略，但同步范围不能依赖人工记忆。`infra/powersync-required-tables.txt` 是当前最低同步表清单，部署或本地配置必须通过 `scripts/check-powersync-sync-scope.sh` 校验。

## 3. 同步范围

同步范围包括：

- memos；
- assets metadata；
- memo_asset_refs；
- ledger_accounts；
- ledger_categories；
- ledger_transactions；
- tasks；
- reminders；
- calendar_events；
- import_batches；
- import_rows；
- audit_logs；
- tombstones；
- memo_classifications；
- tag_metadata；
- ledger_budgets；
- task_reminder_strategies；
- mcp_capture_sessions；
- mcp_capture_turns。

不直接同步：

- 附件二进制；
- 本地缓存文件；
- 临时上传文件；
- AI 推理上下文缓存；
- 可重新计算的首页 overview 缓存；
- 可重新计算的统计图表缓存。

## 4. 附件同步

附件分两部分：

```text
metadata：通过数据库同步
binary：通过对象存储上传/下载
```

本地保存：

- asset metadata；
- local_cache_path；
- cache_status。

云端保存：

- storage_key；
- mime_type；
- sha256；
- size；
- visibility。

## 5. 离线写入

离线时允许：

- 新建/编辑备忘录；
- 新建/编辑账单；
- 新建/编辑任务；
- 引用已存在本地缓存附件；
- 添加本地待上传附件。

离线时不保证：

- App 内 AI；
- 云端 MCP；
- 外部机器人；
- 外部链接预览；
- 新附件云端上传。

## 6. 冲突策略

MVP 阶段采用简单策略。

### 6.1 备忘录

同一字段冲突时使用 last-write-wins。后续长文档可考虑版本历史或 CRDT。

### 6.2 账单

账单更强调可审计。每次修改生成 audit log。冲突时以最新 revision 为准，但保留 before/after snapshot。

### 6.3 任务

任务状态以最新操作为准。完成/取消操作必须写 audit log。

### 6.4 删除

删除不直接物理删除。先进入状态机：

```text
active → ai_trashed / user_trashed → purged
```

## 7. PowerSync 注意事项

开发时需要避免多个进程直接写同一个 SQLite 文件。

Windows 本地 MCP 如果要写入本地数据，应通过本地 Core Bridge，而不是直接绕过客户端数据层。

推荐桌面结构：

```text
Flutter Desktop
      ↓
Local Core Bridge
      ↓
PowerSync SQLite

Local MCP
      ↓
Local Core Bridge
      ↓
PowerSync SQLite
```

## 8. 同步失败处理

必须实现：

- 同步状态提示；
- 最近同步时间；
- 同步失败重试；
- 附件上传失败重试；
- 导入失败可回滚；
- 无法解决冲突时进入 conflict 状态。

## 9. 数据完整性要求

所有写入必须满足：

- 主业务表更新；
- audit_logs 写入；
- revision 增加；
- 删除状态正确；
- 附件引用正确；
- 本地/云端 ID 一致。

## 10. 不允许的行为

禁止：

- AI 直接写数据库；
- 附件二进制塞进 PostgreSQL；
- Flutter 和 Local MCP 同时绕开数据层直写 SQLite；
- CSV 导入直接写正式账单；
- 删除时直接物理删除数据。
