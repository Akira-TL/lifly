# 36. Ledger Expense 写入切片说明

## 1. 目标

本切片对应 Issue #14 / LC-0006，目标是让以下两条路径复用同一个 ledger transaction service：

```text
POST /api/v1/mcp/expense/create
capture_parse -> capture_commit 中的 expense_create action
```

## 2. 当前写入路径

### 2.1 Direct expense_create

```text
POST /api/v1/mcp/expense/create
    ↓
LedgerTransactionCreate Pydantic validation
    ↓
app.modules.ledger.service.create_ledger_transaction_record
    ↓
ledger_transactions 表写入
    ↓
audit_logs 写入，actor_type=ai，source_channel=mcp，tool_name=expense_create
    ↓
返回 transaction / undo_token
```

### 2.2 capture_commit expense action

```text
POST /api/v1/mcp/capture/parse
    ↓
返回 capture_id 和 expense_create action
    ↓
POST /api/v1/mcp/capture/commit
    ↓
读取 CAPTURE_STORE[capture_id]
    ↓
LedgerTransactionCreate Pydantic validation
    ↓
app.modules.ledger.service.create_ledger_transaction_record
    ↓
ledger_transactions 表写入
    ↓
audit_logs 写入，actor_type=ai，source_channel=mcp，tool_name=capture_commit
    ↓
created_entities 记录 {type: ledger_transaction, id}
```

## 3. 不在本切片处理的内容

```text
不修改数据库 schema
不新增 MCP tool
不处理 task_create
不处理 CSV import
不做 UI
不引入复杂复式账本逻辑
```

## 4. 本地验证

启动 API：

```bash
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

### 4.1 Direct expense smoke test

```bash
curl -X POST http://localhost:8310/api/v1/mcp/expense/create \
  -H 'Content-Type: application/json' \
  -d '{"amount":18.5,"currency":"CNY","direction":"expense","merchant":"Coffee Shop","note":"expense_create smoke test"}'
```

预期：

```text
返回 transaction 和 undo_token
transaction.status = active
transaction.amount = 18.5
```

### 4.2 capture_parse -> capture_commit expense smoke test

```bash
CAPTURE_ID=$(curl -s -X POST http://localhost:8310/api/v1/mcp/capture/parse \
  -H 'Content-Type: application/json' \
  -d '{"text":"今天咖啡花了18.5元","timezone":"Asia/Shanghai","locale":"zh-CN"}' \
  | jq -r '.capture_id')

curl -X POST http://localhost:8310/api/v1/mcp/capture/commit \
  -H 'Content-Type: application/json' \
  -d "{\"capture_id\":\"$CAPTURE_ID\"}"
```

预期：

```text
返回 committed=true
created_entities 包含 type=ledger_transaction
```

### 4.3 invalid amount validation

```bash
curl -i -X POST http://localhost:8310/api/v1/mcp/expense/create \
  -H 'Content-Type: application/json' \
  -d '{"amount":0,"currency":"CNY","direction":"expense"}'
```

预期：

```text
HTTP 422
```

## 5. Follow-up

完成本切片后，下一步建议继续：

```text
LC-0007: Extract task service and refactor task_create / capture_commit task action
```
