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

### 13.1 Home Overview

```text
GET /api/v1/home/overview
```

返回结构方向：

```text
schema_version
generated_at
user_timezone
attention_items[]
today_metrics
finance_overview
finance_insights[]
recent_activity[]
sync_summary
import_summary
settings_summary
```

`/dashboard` 保留为轻量统计兼容接口，产品化首页走 `/home/overview`。

### 13.2 Ledger Overview

```text
GET /api/v1/ledger/overview?period=YYYY-MM
GET /api/v1/ledger/categories/summary?period=YYYY-MM&direction=expense
GET /api/v1/ledger/insights?period=YYYY-MM
```

服务端负责预算进度、分类占比、月环比和消费洞察。客户端只渲染返回结果。

### 13.3 Memo Classifications

```text
GET  /api/v1/memos?tag=&classification_status=&type=&limit=&cursor=
GET  /api/v1/memos/{memo_id}/classifications
POST /api/v1/memos/{memo_id}/classifications/confirm
POST /api/v1/memos/{memo_id}/classifications/reject
GET  /api/v1/tags/summary?kind=memo
```

### 13.4 Task Reminder Strategies

```text
GET  /api/v1/tasks?group=today|urgent|warning|all
GET  /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
```

### 13.5 Capture Sessions

```text
POST /api/v1/capture/sessions
POST /api/v1/capture/sessions/{session_id}/turns
POST /api/v1/capture/sessions/{session_id}/commit
POST /api/v1/capture/sessions/{session_id}/undo
```

这些接口应复用当前 capture parse / commit / undo 的业务能力，不绕过审计和撤销边界。
