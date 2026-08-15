# MCP 服务设计

## 1. MCP 目标

MCP 是 Lifly 的 AI 接入边界。所有 AI、机器人、Hermes、OpenClaw 等外部系统必须通过 MCP 工具访问 Lifly 能力。

MCP 的核心职责不是“替代后端 API”，而是把自然语言和 AI 工具调用转成受控的结构化操作。

---

## 2. MCP 形态

### 2.1 Cloud MCP

- 类型：远程 MCP；
- 传输：Streamable HTTP；
- 运行位置：云端；
- 使用场景：App 内 AI、机器人、Hermes/OpenClaw 在线模式；
- 认证：Bearer Token / API Token。

### 2.2 Local MCP

- 类型：本地 MCP；
- 传输：stdio；
- 运行位置：Windows 桌面端；
- 使用场景：本地 Hermes、本地模型、离线 AI、私有部署；
- 认证：本机授权；
- 写入：通过 Local Core Bridge 写入本地 SQLite。

---

## 3. 设计原则

1. Cloud MCP 和 Local MCP 共用 tool schema；
2. MCP 工具不直接操作数据库；
3. 所有写操作必须写 audit log；
4. 所有删除必须进入删除状态机；
5. 工具数量必须控制，避免 Agent 乱调用；
6. `capture_parse` 和 `capture_commit` 是 AI 混合输入的核心；
7. tool schema 必须先进入 `packages/protocol`，再被 Cloud MCP / Local MCP / 测试复用。

---

## 4. Schema Source of Truth

Lifly MCP v0.1 的 schema source of truth 是：

```text
packages/protocol/src/mcp/tool-schemas.ts
```

这个包负责定义：

- 第一版冻结工具名；
- 每个工具的输入 schema；
- 工具描述；
- schema contract tests；
- Cloud MCP 与 Local MCP 可复用的协议类型。

当前后端中的 Python FastMCP 实现是 M0/M1 阶段的运行实现。后续是否迁移为独立 TypeScript Cloud MCP，需要通过 ADR 决定。

---

## 5. 第一版工具清单

```text
capture_parse
capture_commit
capture_undo

memo_create
memo_search

expense_create
expense_search
expense_summary

task_create
task_list
task_complete

asset_create_upload_url
asset_register_external_url
```

禁止新增未经文档、schema、测试批准的 MCP tool。

---

## 6. capture_parse

### 作用

把用户自然语言解析为候选动作，但不正式写入。

### 输入

```json
{
  "text": "今天中午食堂花了18，晚上8点提醒我改页面，记一下今天有点累",
  "timezone": "Asia/Shanghai",
  "locale": "zh-CN"
}
```

### 输出

```json
{
  "capture_id": "uuid",
  "actions": [
    {
      "type": "expense_create",
      "payload": {
        "amount": 18,
        "currency": "CNY",
        "merchant": "食堂",
        "category_hint": "餐饮",
        "occurred_at": "2026-06-21T12:00:00+08:00"
      },
      "confidence": 0.93
    },
    {
      "type": "task_create",
      "payload": {
        "title": "改页面",
        "remind_at": "2026-06-21T20:00:00+08:00"
      },
      "confidence": 0.91
    },
    {
      "type": "memo_create",
      "payload": {
        "type": "journal",
        "content_markdown": "今天有点累"
      },
      "confidence": 0.88
    }
  ],
  "requires_confirmation": false
}
```

---

## 7. capture_commit

### 作用

确认执行 `capture_parse` 产生的动作。当前实现要求先调用 `capture_parse` 获取 `capture_id`，再调用 `capture_commit`。不要直接把任意 `actions` 数组传给 `capture_commit`。

### 输入

```json
{
  "capture_id": "uuid",
  "selected_action_indexes": [0, 1, 2]
}
```

### 输出

```json
{
  "committed": true,
  "created_entities": [
    {"type": "ledger_transaction", "id": "uuid"},
    {"type": "task", "id": "uuid"},
    {"type": "memo", "id": "uuid"}
  ],
  "undo_token": "token"
}
```

### 当前 memo_create action 运行路径

当 `capture_commit` 执行 `memo_create` action 时，当前路径为：

```text
POST /api/v1/mcp/capture/commit
    ↓
读取 CAPTURE_STORE[capture_id]
    ↓
遍历 actions 中的 memo_create
    ↓
MemoCreate Pydantic validation
    ↓
app.modules.memos.service.create_memo_record
    ↓
memos 表写入
    ↓
audit_logs 写入，actor_type=ai，source_channel=mcp，tool_name=capture_commit
    ↓
created_entities 记录 {type: memo, id}
```

这保证了直接 `memo_create` tool 与混合输入 `capture_commit` 的 memo 写入路径复用同一个业务层，避免 MCP endpoint 内部直接构造 `Memo`。

### 本地验证

先调用 `capture_parse`：

```bash
CAPTURE_ID=$(curl -s -X POST http://localhost:8210/api/v1/mcp/capture/parse \
  -H 'Content-Type: application/json' \
  -d '{"text":"记一下 capture_commit 测试","timezone":"Asia/Shanghai","locale":"zh-CN"}' \
  | jq -r '.capture_id')
```

再提交：

```bash
curl -X POST http://localhost:8210/api/v1/mcp/capture/commit \
  -H 'Content-Type: application/json' \
  -d "{\"capture_id\":\"$CAPTURE_ID\"}"
```

预期：

- 返回 `committed=true`；
- `created_entities` 包含 memo；
- `memos` 表新增记录；
- `audit_logs` 写入 `tool_name=capture_commit`。

---

## 8. capture_undo

撤销最近一次 `capture_commit`。

```json
{
  "undo_token": "token"
}
```

---

## 9. memo_create

### 输入

```json
{
  "type": "memo",
  "title": "标题",
  "content_markdown": "内容",
  "tags": ["项目", "想法"]
}
```

`type` 允许值：

```text
memo
journal
clip
doc
```

### 当前运行路径

`memo_create` 的当前 M0/M3 最小运行切片为：

```text
Cloud MCP memo_create
    ↓
POST /api/v1/mcp/memo/create
    ↓
MemoCreate Pydantic validation
    ↓
app.modules.memos.service.create_memo_record
    ↓
memos 表写入
    ↓
audit_logs 写入，actor_type=ai，source_channel=mcp，tool_name=memo_create
    ↓
返回 memo_id/status/memo/undo_token
```

MCP router 不应绕过 `app.modules.memos.service` 直接构造 `Memo`。后续 memo API、Cloud MCP、Local MCP 都应逐步复用同一业务层。

### 输出

```json
{
  "memo_id": "uuid",
  "status": "active",
  "memo": {
    "id": "uuid",
    "type": "memo",
    "title": "标题",
    "content_markdown": "内容",
    "tags": ["项目", "想法"],
    "status": "active"
  },
  "undo_token": "uuid"
}
```

### 本地验证

```bash
curl -X POST http://localhost:8210/api/v1/mcp/memo/create \
  -H 'Content-Type: application/json' \
  -d '{"type":"memo","title":"MCP memo smoke test","content_markdown":"hello from memo_create","tags":["mcp","smoke"]}'
```

预期：返回 `memo_id`、`status=active`、`memo` 和 `undo_token`。

无效输入应返回 `422`，例如：

```bash
curl -X POST http://localhost:8210/api/v1/mcp/memo/create \
  -H 'Content-Type: application/json' \
  -d '{"type":"invalid","content_markdown":"bad"}'
```

---

## 10. expense_create

```json
{
  "amount": 18,
  "currency": "CNY",
  "direction": "expense",
  "category_hint": "餐饮",
  "merchant": "食堂",
  "occurred_at": "2026-06-21T12:00:00+08:00",
  "note": ""
}
```

`direction` 允许值：

```text
expense
income
transfer
```

---

## 11. task_create

```json
{
  "title": "改 Lifly 登录页",
  "description": "",
  "due_at": null,
  "remind_at": "2026-06-21T20:00:00+08:00",
  "priority": "normal"
}
```

`priority` 允许值：

```text
low
normal
high
urgent
```

---

## 12. asset_create_upload_url

用于内部附件上传。

```json
{
  "filename": "image.png",
  "mime_type": "image/png",
  "size_bytes": 123456,
  "asset_type": "image"
}
```

返回：

```json
{
  "asset_id": "uuid",
  "upload_url": "https://...",
  "expires_at": "2026-06-21T10:10:00Z"
}
```

---

## 13. asset_register_external_url

用于外部链接/图床/第三方文档。

```json
{
  "external_url": "https://example.com/image.png",
  "asset_type": "image",
  "title": "图片"
}
```

---

## 14. 错误码

| 错误码 | 含义 |
|---|---|
| AUTH_REQUIRED | 未认证 |
| PERMISSION_DENIED | 无权限 |
| INVALID_ARGUMENT | 参数错误 |
| ENTITY_NOT_FOUND | 实体不存在 |
| SYNC_UNAVAILABLE | 同步不可用 |
| ASSET_UPLOAD_FAILED | 附件上传失败 |
| IMPORT_BATCH_INVALID | 导入批次无效 |
| AI_PARSE_LOW_CONFIDENCE | 解析置信度过低 |

---

## 15. 当前实现说明

截至 v0.1 M0/M3 阶段：

- Python FastMCP 已经提供 Cloud MCP 的运行实现；
- `packages/protocol` 提供共享 schema 和 contract tests；
- `memo_create` 已完成第一条 MCP 写入 vertical slice；
- `capture_commit` 的 memo_create action 已复用 memo service；
- 后续 Cloud MCP / Local MCP 都必须对齐 `packages/protocol`；
- 是否将 Cloud MCP 从 Python 内嵌实现迁移为独立 TypeScript 服务，需要单独 ADR。
