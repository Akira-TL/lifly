# 后端 API 与服务设计

## 1. 后端职责

后端负责：

- 用户认证；
- 业务 API；
- PowerSync 后端集成；
- MCP tool handler 调用；
- 附件签名 URL；
- CSV 导入；
- 审计日志；
- 回收站；
- 导出；
- 后台任务。

## 2. 服务结构

```text
services/api/
├─ app/
│  ├─ main.py
│  ├─ modules/
│  │  ├─ auth/
│  │  ├─ users/
│  │  ├─ memos/
│  │  ├─ assets/
│  │  ├─ ledger/
│  │  ├─ tasks/
│  │  ├─ imports/
│  │  ├─ audit/
│  │  ├─ trash/
│  │  └─ mcp_bridge/
│  ├─ core/
│  ├─ db/
│  ├─ schemas/
│  └─ workers/
└─ tests/
```

## 3. API 分层

### 3.1 Public API

给客户端调用：

```text
/auth
/memos
/assets
/ledger
/tasks
/imports
/audit
/trash
/export
```

### 3.2 Internal API

给 MCP Server 调用：

```text
/internal/capture/parse
/internal/capture/commit
/internal/memo/create
/internal/expense/create
/internal/task/create
```

### 3.3 Worker API

异步任务：

- CSV 解析；
- 缩略图；
- 导出打包；
- 清理 purged 数据；
- 附件垃圾回收。

## 4. 认证

本地模式不需要登录。

云端模式需要登录。API 使用 access token。外部机器人和 MCP Client 使用可吊销 API Token。

## 5. 请求追踪

所有 API 请求必须生成 request_id，并贯穿：

- API log；
- MCP request；
- audit log；
- worker job；
- error report。

## 6. 业务写入流程

任何写入必须经过：

```text
参数校验
    ↓
权限检查
    ↓
业务规则
    ↓
写入主表
    ↓
写入 audit_logs
    ↓
返回结果
```

## 7. 删除流程

删除 API 不允许直接物理删除。必须进入状态机。

用户删除：

```text
active → user_trashed
```

AI 删除：

```text
active → ai_trashed
```

后台清理：

```text
user_trashed 超过 30 天 → purged
```

## 8. 附件上传流程

```text
客户端请求 create_upload_url
    ↓
后端创建 asset metadata
    ↓
后端生成 presigned upload URL
    ↓
客户端上传对象存储
    ↓
客户端通知 upload_complete
    ↓
后端校验 size/hash/mime
```

## 9. CSV 导入流程

```text
上传 CSV
    ↓
创建 import_batch
    ↓
解析 import_rows
    ↓
预览
    ↓
规则/AI 分类
    ↓
用户确认 commit
    ↓
生成 ledger_transactions
    ↓
写 audit_logs
```

## 10. 错误响应格式

```json
{
  "error": {
    "code": "INVALID_ARGUMENT",
    "message": "金额不能为空",
    "details": {},
    "request_id": "..."
  }
}
```

## 11. 权限隔离

所有查询必须按 user_id 过滤。任何 API 不得允许客户端传入并访问其他用户数据。

## 12. 当前已实现 API 清单

服务端当前统一挂载在 `/api/v1` 下。

### 12.1 Auth

```text
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/api-tokens
GET  /api/v1/auth/api-tokens
POST /api/v1/auth/api-tokens/{token_id}/revoke
```

### 12.2 Memos

```text
POST   /api/v1/memos
GET    /api/v1/memos
GET    /api/v1/memos/{memo_id}
PUT    /api/v1/memos/{memo_id}
DELETE /api/v1/memos/{memo_id}
GET    /api/v1/memos/{memo_id}/assets
POST   /api/v1/memos/{memo_id}/assets
DELETE /api/v1/memos/{memo_id}/assets/{asset_id}
```

### 12.3 Ledger

```text
POST   /api/v1/ledger/transactions
GET    /api/v1/ledger/transactions
GET    /api/v1/ledger/transactions/{tx_id}
PUT    /api/v1/ledger/transactions/{tx_id}
DELETE /api/v1/ledger/transactions/{tx_id}
GET    /api/v1/ledger/summary
GET    /api/v1/ledger/categories
```

### 12.4 Tasks

```text
POST   /api/v1/tasks
GET    /api/v1/tasks
GET    /api/v1/tasks/{task_id}
PUT    /api/v1/tasks/{task_id}
POST   /api/v1/tasks/{task_id}/complete
DELETE /api/v1/tasks/{task_id}
```

### 12.5 Assets

```text
POST   /api/v1/assets/create-upload-url
POST   /api/v1/assets/register-external-url
POST   /api/v1/assets/{asset_id}/upload-complete
GET    /api/v1/assets/{asset_id}/download-url
GET    /api/v1/assets
GET    /api/v1/assets/{asset_id}
PUT    /api/v1/assets/{asset_id}
DELETE /api/v1/assets/{asset_id}
```

### 12.6 Import / Export

```text
POST /api/v1/imexport/import/upload
GET  /api/v1/imexport/import/{batch_id}/preview
POST /api/v1/imexport/import/{batch_id}/commit
POST /api/v1/imexport/import/{batch_id}/rollback
GET  /api/v1/imexport/import/batches
GET  /api/v1/imexport/import/{batch_id}
POST /api/v1/imexport/export
GET  /api/v1/imexport/export/stream
```

### 12.7 MCP

```text
POST /api/v1/mcp/capture/parse
POST /api/v1/mcp/capture/commit
POST /api/v1/mcp/capture/undo
POST /api/v1/mcp/memo/create
POST /api/v1/mcp/memo/search
POST /api/v1/mcp/expense/create
POST /api/v1/mcp/expense/search
POST /api/v1/mcp/expense/summary
POST /api/v1/mcp/task/create
POST /api/v1/mcp/task/list
POST /api/v1/mcp/task/complete
POST /api/v1/mcp/asset/create-upload-url
POST /api/v1/mcp/asset/register-external-url
```

### 12.8 Search / Dashboard / Sync / Audit / Plugins

```text
GET  /api/v1/search
GET  /api/v1/dashboard
GET  /api/v1/sync/credentials
POST /api/v1/sync/push
GET  /api/v1/audit
GET  /api/v1/audit/ai-summary
GET  /api/v1/trash
POST /api/v1/trash/{entity_type}/{entity_id}/restore
POST /api/v1/trash/purge
GET  /api/v1/plugins
GET  /api/v1/robots
GET  /api/v1/robots/{robot_id}
GET  /api/v1/robots/{robot_id}/system-prompt
```

## 13. 下一阶段正式 API 契约

以下接口属于长期产品地基，未实现前客户端不能写假数据。

这些 API 是正常联网状态下的云端读取入口，但不是手机端的唯一计算来源。Lifly 的运行策略是云端拉取和同步优先；云端失败、断网或弱网时，手机端通过 Local Core / PowerSync 本地数据计算同构 read model 兜底。

同构 read model 必须包含：

```text
schema_version
generated_at
user_timezone
source_mode: local / api / fallback
```

### 13.1 Home Overview

本地主路径：

```text
LocalCoreBridge.getHomeOverview(params, context)
```

云端同构兜底：

```text
GET /api/v1/home/overview
```

返回结构方向：

```text
schema_version
generated_at
user_timezone
source_mode
attention_items[]
today_metrics
finance_overview
  month_income / month_expense / transaction_count
  budget_state / budget_amount / budget_used / budget_progress / budget_remaining / currency
  category_breakdown[]
  insights[]
finance_insights[]
recent_activity[]
sync_summary
  status / mode
  connected / connecting / downloading / uploading / has_synced
  last_synced_at / error
  powersync_configured
  pending_asset_count / failed_asset_count / synced_asset_count
import_summary
  status / latest_batch_id / source_provider / filename
  total_rows / valid_rows / duplicate_rows
  created_at / committed_at / rolled_back_at
settings_summary
  status / mode / data_mode / timezone
  local_core_available / database_path
  database_configured / powersync_configured / object_storage_configured
```

`/home/overview` 是产品化首页云端正常读取入口；`/dashboard` 保留为轻量统计兼容接口。客户端云端读取失败时再 fallback 到本地同构 read model。

服务端不能推断某台客户端是否在线，因此服务端 `sync_summary` 只返回可验证的 PowerSync 配置状态与附件同步统计；客户端本地 `sync_summary` 读取 PowerSync `currentStatus`，返回真实连接、上传、下载、最近同步和错误状态。`import_summary` 来自最新 `import_batches` 记录，不能固定返回 `idle`；`settings_summary` 只暴露配置是否完整，不返回连接串、密钥等敏感值。

### 13.2 Ledger Overview

本地主路径：

```text
LocalCoreBridge.getLedgerOverview(period)
LocalCoreBridge.getLedgerCategorySummary(period, direction)
LocalCoreBridge.getLedgerInsights(period)
```

云端同构兜底：

```text
GET /api/v1/ledger/overview?period=YYYY-MM
GET /api/v1/ledger/categories/summary?period=YYYY-MM&direction=expense
GET /api/v1/ledger/insights?period=YYYY-MM
```

预算进度、分类占比和基础消费洞察正常由云端接口拉取；同步后本地也可计算，并在云端失败时由 repository fallback。客户端只渲染 repository 返回的同构 DTO，不关心数据来自 api 还是 fallback。

预算管理接口：

```text
GET    /api/v1/ledger/budgets?period=YYYY-MM&status=active|deleted|all&category_id=
POST   /api/v1/ledger/budgets
GET    /api/v1/ledger/budgets/{budget_id}
PUT    /api/v1/ledger/budgets/{budget_id}
DELETE /api/v1/ledger/budgets/{budget_id}
```

预算写入字段：

```text
period_type: 当前固定 month
period_key: YYYY-MM
category_id: null 表示总预算；非 null 表示支出分类预算
amount: 必须大于 0
currency: 默认 CNY
alert_threshold: 大于 0 且不超过 1
status: active / deleted
revision: 用于 PowerSync 陈旧写入判定
```

同一用户、月份和分类范围只能存在一个 active 预算；分类预算只能绑定 active 的 expense 分类。删除使用软删除并写入 `budget.delete` 审计，恢复通过更新 `status=active` 并写入 `budget.restore`。Local Core 与服务端返回同构预算实体；预算列表云端读取失败时可 fallback 到本地。写操作不在不确定的云端失败后自动重复落地本地，避免一次请求形成双写，离线写入应明确使用 Local Core / PowerSync 路径。

### 13.3 Memo Classifications

本地主路径：

```text
LocalCoreBridge.searchMemos(filters)
LocalCoreBridge.getMemoClassifications(memoId)
LocalCoreBridge.generateMemoClassifications(memoId)
LocalCoreBridge.getTagSummary(kind)
LocalCoreBridge.listTagMetadata(kind)
LocalCoreBridge.upsertTagMetadata(input)
LocalCoreBridge.deleteTagMetadata(name)
```

云端正常读取入口：

```text
GET  /api/v1/memos?tag=&classification_status=&type=&limit=&cursor=
GET  /api/v1/memos/{memo_id}/classifications
POST /api/v1/memos/{memo_id}/classifications/generate
POST /api/v1/memos/{memo_id}/classifications/confirm
POST /api/v1/memos/{memo_id}/classifications/reject
GET  /api/v1/tags/summary?kind=memo
GET  /api/v1/tags/metadata?kind=memo
POST /api/v1/tags/metadata
DELETE /api/v1/tags/metadata/{tag_name}?kind=memo
```

边界：`Memo.tags` 只做旧字段兼容，不代表 AI 分类状态；`rejected` 分类不得进入标签统计。备忘创建/更新会自动生成 suggested 分类；用户确认后才进入 confirmed 语义。

### 13.4 Task Reminder Strategies

本地主路径：

```text
LocalCoreBridge.listTasks(group)
LocalCoreBridge.generateTaskReminderStrategy(taskId)
LocalCoreBridge.getTaskReminderStrategy(taskId)
LocalCoreBridge.confirmTaskReminderStrategy(taskId)
LocalCoreBridge.dismissTaskReminderStrategy(taskId)
LocalCoreBridge.listTaskReminders(status)
LocalCoreBridge.claimDueTaskReminders(limit, now, leaseSeconds)
LocalCoreBridge.markTaskReminderDelivered(reminderId, dispatchToken, externalId)
LocalCoreBridge.markTaskReminderFailed(reminderId, dispatchToken, error, retryAfterSeconds)
LocalCoreBridge.retryTaskReminder(reminderId)
LocalCoreBridge.cancelTaskReminder(reminderId)
```

云端正常读取入口：

```text
GET  /api/v1/tasks?group=today|urgent|warning|all
GET  /api/v1/tasks/reminders
POST /api/v1/tasks/reminders/claim
POST /api/v1/tasks/reminders/{reminder_id}/delivered
POST /api/v1/tasks/reminders/{reminder_id}/failed
POST /api/v1/tasks/reminders/{reminder_id}/retry
POST /api/v1/tasks/reminders/{reminder_id}/cancel
GET  /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/generate
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
```

边界：没有策略时返回 null，不伪造 AI 预警；任务创建/更新会生成 suggested 策略；策略确认后才更新 Task.remind_at，并写入 pending reminders；dismissed 策略不参与任务分组。Reminder 状态只使用 `pending / delivered / failed / cancelled`；派发前通过 claim 生成短期 `dispatch_token + lease_until`，平台适配器使用 reminder ID 作为幂等键，送达或失败回写时必须携带当前 token。失败按指数退避写入 `next_attempt_at`，耗尽 `max_attempts` 后停止自动重试，手动 retry 可重置次数。任务完成、取消、删除或策略 dismiss 会取消尚未送达的提醒。

### 13.5 Capture Sessions

Capture 是连续聊天会话，不再把一次 `parse / commit` 视为整个会话的终点。每一轮用户输入、AI 候选动作、执行结果、修改和撤销都写入独立 turn；同一 session 可以持续追加多轮。

本地主路径：

```text
LocalCoreBridge.listCaptureAssets(input, context)
LocalCoreBridge.captureParse(input, context)
LocalCoreBridge.listCaptureSessions(input, context)
LocalCoreBridge.getCaptureSession(input, context)
LocalCoreBridge.appendCaptureTurn(input, context)
LocalCoreBridge.reviseCaptureAction(input, context)
LocalCoreBridge.captureCommit(input, context)
LocalCoreBridge.captureUndo(input, context)
LocalCoreBridge.dismissCaptureSession(input, context)
```

云端入口：

```text
POST /api/v1/mcp/capture/parse
GET  /api/v1/mcp/capture/sessions
GET  /api/v1/mcp/capture/sessions/{capture_id}
POST /api/v1/mcp/capture/sessions/{capture_id}/turns
POST /api/v1/mcp/capture/sessions/{capture_id}/turns/{turn_id}/revise
POST /api/v1/mcp/capture/commit
POST /api/v1/mcp/capture/undo
POST /api/v1/mcp/capture/sessions/{capture_id}/dismiss
```

`capture/parse` 创建 session，并分别写入 user turn 与 assistant action turn。`append turn` 在同一 session 中继续记录用户输入和新的候选动作。`commit` 必须指定或解析到具体 assistant turn，只提交该轮候选动作；执行结果实体和 `undo_token` 保存在该 turn 上，session 仍保持 active。用户修改未执行候选动作时，创建新的 revised turn，并通过 `supersedes_turn_id` 保留修改链。已经 committed / partial 的 turn 必须先 undo，实体转为 `ai_trashed` 且原 turn 变为 undone，之后才允许继续修改并重新提交。dismiss 只关闭会话，不删除历史。

本地持久化表：

```text
mcp_capture_sessions
mcp_capture_turns
mcp_undo_actions
```

`asset_ids` 和解析后的 `asset_context` 按 turn 持久化并经 PowerSync 同步。`capture/parse` 与 `append turn` 响应中的 `asset_context` 使用统一状态：`ready / metadata_only / pending_upload / unsupported / missing / inactive / failed`，同时返回 `extractor`、`error` 和 `required_capability`，客户端不能把尚未支持的附件伪装成已识别。

当前服务端会对已同步、大小不超过 256 KiB 的 UTF-8 纯文本、Markdown、CSV、JSON、XML 附件进行安全读取，并把最多 20,000 字符的内容加入解析上下文；所有附件合计最多加入 30,000 字符。PDF 返回 `pdf_text_extraction`，图片返回 `ocr_or_vision`，音频返回 `speech_to_text`，外部链接返回 `external_content_fetch`。本地 Local Core 当前只解析 PowerSync 中的附件元数据与能力状态，不读取本地二进制；引用仍会进入 memo 候选 payload。云端 AI 可以用于解析，但不能成为会话记录、修改、确认或撤销链路的唯一依赖。
