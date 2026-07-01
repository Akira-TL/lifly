# MCP v0.1 Smoke Test

This document describes the local smoke test for the frozen Lifly MCP v0.1 tool surface.

The script is intentionally a shell-based smoke test rather than a full backend test suite. Its purpose is to let an AI agent or developer quickly verify that the running local API still supports the complete MCP v0.1 contract after a backend, schema, or service-layer change.

## Script

```bash
bash scripts/smoke-mcp-v0.1.sh
```

Default API base URL:

```text
http://localhost:8310
```

Override it with:

```bash
LIFLY_API_BASE_URL=http://localhost:8310 bash scripts/smoke-mcp-v0.1.sh
```

## Prerequisites

Required command-line tools:

```text
curl
jq
```

Required local services:

```text
PostgreSQL
MinIO or compatible object storage
Lifly FastAPI service
```

Start the API from `services/api`:

```bash
uv run uvicorn app.main:app --reload --port 8310
```

The test assumes the local development user remains:

```text
local-dev
```

## Coverage

The script validates the full MCP v0.1 runtime surface currently implemented by the API.

### Health

```text
GET /api/v1/health
```

### Memo tools

```text
POST /api/v1/mcp/memo/create
POST /api/v1/mcp/memo/search
```

Checks:

```text
memo_create returns memo_id and undo_token
memo_search can find the created memo
invalid memo type returns 422
```

### Expense tools

```text
POST /api/v1/mcp/expense/create
POST /api/v1/mcp/expense/search
POST /api/v1/mcp/expense/summary
```

Checks:

```text
expense_create returns transaction.id
expense_search can find the created transaction
expense_summary returns current_month total and count
amount=0 returns 422
```

### Task tools

```text
POST /api/v1/mcp/task/create
POST /api/v1/mcp/task/list
POST /api/v1/mcp/task/complete
```

Checks:

```text
task_create returns a todo task
task_list can find the created task
task_complete marks the task as done and sets completed_at
missing task_id returns 422
```

### Asset tools

```text
POST /api/v1/mcp/asset/create-upload-url
POST /api/v1/mcp/asset/register-external-url
```

Checks:

```text
asset_create_upload_url returns asset_id, storage_key, upload_url, and pending internal asset
asset_register_external_url returns synced external asset
invalid asset_type returns 422
```

This smoke test does not upload binary bytes to object storage. It only validates the metadata row and presigned upload URL creation path.

### Capture tools

```text
POST /api/v1/mcp/capture/parse
POST /api/v1/mcp/capture/commit
POST /api/v1/mcp/capture/undo
```

Checks:

```text
capture_parse returns capture_id and actions
capture_commit creates at least one entity and returns undo_token
capture_undo can undo the committed entity
reusing the same undo_token returns 404
```

## Expected output

A passing run prints one line per check:

```text
[PASS] health
[PASS] memo_create
[PASS] memo_search
...
All Lifly MCP v0.1 smoke checks passed: <N>
```

## Failure behavior

The script fails fast.

On failure it prints:

```text
[FAIL] <reason>
[response]
<last response body>
```

Common causes:

| Symptom | Likely cause |
| --- | --- |
| `Missing required command: jq` | Install `jq` locally. |
| `health request failed` | API is not running or `LIFLY_API_BASE_URL` is wrong. |
| HTTP 500 on asset upload URL | MinIO/S3 configuration is not running or not reachable. |
| Search cannot find created entity | The write path succeeded but search filter or response shape changed. |
| `capture_parse` returns no actions | Parse engine behavior changed and needs contract review. |

## Scope boundary

This script is not a replacement for pytest integration tests. It is a developer-facing smoke test for the running local stack.

The next test layer should be:

```text
services/api/tests/test_mcp_*.py
```

Those tests should run in CI after the API test harness is established.
