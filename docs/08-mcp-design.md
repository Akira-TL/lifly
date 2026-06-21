# 08. MCP 服务设计

## 1. MCP 目标

MCP 是 Lifily 的 AI 接入边界。所有 AI、机器人、Hermes、OpenClaw 等外部系统必须通过 MCP 工具访问 Lifily 能力。

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

## 3. 设计原则

1. Cloud MCP 和 Local MCP 共用 tool schema；
2. MCP 工具不直接操作数据库；
3. 所有写操作必须写 audit log；
4. 所有删除必须进入删除状态机；
5. 工具数量必须控制，避免 Agent 乱调用；
6. capture_parse 和 capture_commit 是 AI 混合输入的核心。

## 4. 第一版工具清单

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

## 5. capture_parse

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

## 6. capture_commit

### 作用

确认执行 capture_parse 产生的动作。

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

## 7. capture_undo

撤销最近一次 capture_commit。

```json
{
  "undo_token": "token"
}
```

## 8. memo_create

```json
{
  "type": "memo",
  "title": "标题",
  "content_markdown": "内容",
  "tags": ["项目", "想法"],
  "asset_ids": []
}
```

## 9. expense_create

```json
{
  "amount": 18,
  "currency": "CNY",
  "direction": "expense",
  "category_id": "optional",
  "category_hint": "餐饮",
  "merchant": "食堂",
  "occurred_at": "2026-06-21T12:00:00+08:00",
  "note": ""
}
```

## 10. task_create

```json
{
  "title": "改 PeTalk 登录页",
  "description": "",
  "due_at": null,
  "remind_at": "2026-06-21T20:00:00+08:00",
  "priority": "normal"
}
```

## 11. asset_create_upload_url

用于内部附件上传。

```json
{
  "filename": "image.png",
  "mime_type": "image/png",
  "size_bytes": 123456
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

## 12. asset_register_external_url

用于外部链接/图床/第三方文档。

```json
{
  "external_url": "https://example.com/image.png",
  "asset_type": "image",
  "title": "图片"
}
```

## 13. 错误码

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
