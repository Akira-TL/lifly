# 37. Task Service Slice Verification

## Status

This document verifies Issue #16:

```text
[LC-0007] Refactor MCP task_create and capture_commit task action to reuse task service
```

## Scope

This slice unifies task creation through `services/api/app/modules/tasks/service.py`.

Covered paths:

```text
POST /api/v1/tasks
POST /api/v1/mcp/task/create
POST /api/v1/mcp/capture/parse -> POST /api/v1/mcp/capture/commit, when action type is task_create
```

Not covered:

```text
Full calendar UI
Reminder scheduler
Task notification delivery
Task recurrence
```

## Runtime Path

### Direct MCP task_create

```text
Request JSON
  ↓
TaskCreate Pydantic validation
  ↓
create_task_record(...)
  ↓
tasks insert
  ↓
audit_logs insert, tool_name=task_create
  ↓
return task + undo_token
```

### capture_commit task action

```text
capture_parse
  ↓
capture_commit
  ↓
TaskCreate Pydantic validation
  ↓
create_task_record(...)
  ↓
tasks insert
  ↓
audit_logs insert, tool_name=capture_commit
  ↓
created_entities includes type=task
```

## Local Verification

Start API:

```bash
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

### 1. Direct MCP task_create smoke test

```bash
curl -X POST http://localhost:8310/api/v1/mcp/task/create \
  -H 'Content-Type: application/json' \
  -d '{"title":"Task direct smoke test","description":"created by direct task_create","priority":"high"}'
```

Expected:

```text
response contains task.id
task.title = Task direct smoke test
task.status = active
response contains undo_token
```

### 2. capture_parse -> capture_commit task smoke test

```bash
CAPTURE_ID=$(curl -s -X POST http://localhost:8310/api/v1/mcp/capture/parse \
  -H 'Content-Type: application/json' \
  -d '{"text":"提醒我明天提交 Lifly task service 验证","timezone":"Asia/Shanghai","locale":"zh-CN"}' \
  | jq -r '.capture_id')

echo "$CAPTURE_ID"

curl -X POST http://localhost:8310/api/v1/mcp/capture/commit \
  -H 'Content-Type: application/json' \
  -d "{\"capture_id\":\"$CAPTURE_ID\"}"
```

Expected:

```text
committed=true
created_entities includes type=task
response contains undo_token
```

### 3. Invalid priority validation

```bash
curl -i -X POST http://localhost:8310/api/v1/mcp/task/create \
  -H 'Content-Type: application/json' \
  -d '{"title":"Bad priority","priority":"invalid"}'
```

Expected:

```text
HTTP/1.1 422 Unprocessable Entity
```

### 4. Normal API regression smoke test

```bash
curl -X POST http://localhost:8310/api/v1/tasks \
  -H 'Content-Type: application/json' \
  -d '{"title":"Normal API task regression","description":"created by normal task API","priority":"normal"}'
```

Expected:

```text
success=true
data.title = Normal API task regression
```

## Notes

`task_complete` still uses the MCP router audit helper. This slice focuses on creation paths only, matching memo and expense creation service unification.
