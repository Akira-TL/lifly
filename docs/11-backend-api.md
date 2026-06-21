# 11. 后端 API 与服务设计

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
