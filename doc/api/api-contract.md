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
import_summary
settings_summary
```

`/home/overview` 是产品化首页云端正常读取入口；`/dashboard` 保留为轻量统计兼容接口。客户端云端读取失败时再 fallback 到本地同构 read model。

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
```

云端正常读取入口：

```text
GET  /api/v1/tasks?group=today|urgent|warning|all
GET  /api/v1/tasks/reminders
GET  /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/generate
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
```

边界：没有策略时返回 null，不伪造 AI 预警；任务创建/更新会生成 suggested 策略；策略确认后才更新 Task.remind_at，并写入 pending reminders；dismissed 策略不参与任务分组。

### 13.5 Capture Sessions

当前本地主路径复用现有 Capture tool 语义，并已具备本地持久化：

```text
LocalCoreBridge.captureParse(input, context)
LocalCoreBridge.captureCommit(input, context)
LocalCoreBridge.captureUndo(input, context)
```

本地持久化表：

```text
mcp_capture_sessions
mcp_capture_turns
mcp_undo_actions
```

当前云端入口：

```text
POST /api/v1/mcp/capture/parse
POST /api/v1/mcp/capture/commit
POST /api/v1/mcp/capture/undo
```

云端 parse 会写入 `McpCaptureSession` 与首个 `McpCaptureTurn`；commit 会写入业务实体、audit_logs、mcp_undo_actions，并追加 commit turn；undo 会消费 undo token，将实体转为 ai_trashed，并在能解析 source_capture_id 时追加 undo turn。本地 capture_parse 已具备最小规则拆分，可从一句话生成 task_create / expense_create / memo_create 候选动作；后续继续扩展多轮 append turn、asset_ids 真实解析、STT 和会话恢复。

后续可选兼容 API：

```text
POST /api/v1/capture/sessions
POST /api/v1/capture/sessions/{session_id}/turns
POST /api/v1/capture/sessions/{session_id}/commit
POST /api/v1/capture/sessions/{session_id}/undo
```

这些接口应复用当前 capture parse / commit / undo 的业务能力，不绕过审计和撤销边界。Capture session 和确认结果必须能本地持久化；云端 AI 可以用于解析，但不能成为本地记录、确认、撤销链路的唯一依赖。
