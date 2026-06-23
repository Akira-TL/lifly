# 38. capture_undo 硬化验证说明

## 1. 目标

本切片对应 Issue #18：`[LC-0008] Harden MCP capture_undo request validation and response`。

目标是让 MCP 撤销链路更稳定：

```text
memo_create / expense_create / task_create / capture_commit
    ↓
返回 undo_token
    ↓
capture_undo 使用 undo_token
    ↓
创建的实体进入 ai_trashed
    ↓
写 audit_logs
```

## 2. 变更内容

本切片做三件事：

1. 新增 `CaptureUndoRequest` Pydantic schema；
2. `POST /api/v1/mcp/capture/undo` 使用 schema 校验；
3. response 只把真正撤销成功的实体放入 `entities`，找不到或不支持的实体放入 `failed_entities`。

返回结构：

```json
{
  "undone": 1,
  "entities": [
    {"type": "memo", "id": "..."}
  ],
  "failed_entities": []
}
```

## 3. 本地验证

启动 API：

```bash
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

### 3.1 direct memo_create -> capture_undo

```bash
UNDO_TOKEN=$(curl -s -X POST http://localhost:8310/api/v1/mcp/memo/create \
  -H 'Content-Type: application/json' \
  -d '{"type":"memo","title":"Undo memo smoke test","content_markdown":"to be undone","tags":["undo","smoke"]}' \
  | jq -r '.undo_token')

echo "$UNDO_TOKEN"

curl -X POST http://localhost:8310/api/v1/mcp/capture/undo \
  -H 'Content-Type: application/json' \
  -d "{\"undo_token\":\"$UNDO_TOKEN\"}"
```

预期：

```json
{
  "undone": 1,
  "entities": [{"type":"memo","id":"..."}],
  "failed_entities": []
}
```

### 3.2 重复使用同一个 undo token

```bash
curl -i -X POST http://localhost:8310/api/v1/mcp/capture/undo \
  -H 'Content-Type: application/json' \
  -d "{\"undo_token\":\"$UNDO_TOKEN\"}"
```

预期：

```text
HTTP/1.1 404 Not Found
```

说明：`get_undo_entries(...)` 会 pop 掉 token，因此 token 只能使用一次。

### 3.3 missing undo_token validation

```bash
curl -i -X POST http://localhost:8310/api/v1/mcp/capture/undo \
  -H 'Content-Type: application/json' \
  -d '{}'
```

预期：

```text
HTTP/1.1 422 Unprocessable Entity
```

### 3.4 capture_parse -> capture_commit -> capture_undo

```bash
COMMIT_RESPONSE=$(CAPTURE_ID=$(curl -s -X POST http://localhost:8310/api/v1/mcp/capture/parse \
  -H 'Content-Type: application/json' \
  -d '{"text":"记一下 undo capture_commit 测试","timezone":"Asia/Shanghai","locale":"zh-CN"}' \
  | jq -r '.capture_id') && \
  curl -s -X POST http://localhost:8310/api/v1/mcp/capture/commit \
    -H 'Content-Type: application/json' \
    -d "{\"capture_id\":\"$CAPTURE_ID\"}")

echo "$COMMIT_RESPONSE"
UNDO_TOKEN=$(echo "$COMMIT_RESPONSE" | jq -r '.undo_token')

curl -X POST http://localhost:8310/api/v1/mcp/capture/undo \
  -H 'Content-Type: application/json' \
  -d "{\"undo_token\":\"$UNDO_TOKEN\"}"
```

预期：

```text
undone >= 1
failed_entities = []
```

## 4. 不做内容

本切片不做：

- persistent undo token storage；
- 数据库 schema 变更；
- 新 MCP tool；
- UI；
- 长期撤销历史管理。

当前 undo token 仍然是内存态能力，适合作为 MVP 的短时撤销闭环。