# Lifly API MCP v0.1 Integration Tests

This document describes the backend integration tests for the Lifly MCP v0.1 contract.

## Purpose

The shell smoke script validates the MCP API from a CLI workflow. The Python integration tests provide the next layer of protection so later PRs can run the same MCP contract through test tooling and CI.

These tests currently target a running local API instead of embedding the FastAPI app directly. That keeps the behavior aligned with the actual development stack: FastAPI, PostgreSQL, MinIO, and the current application settings.

## Files

```text
services/api/tests/integration/test_mcp_v0_1_contract.py
```

## Covered checks

The test suite covers:

```text
health version
memo_create
memo_search
memo_create invalid type -> 422
expense_create
expense_search
expense_summary
action amount=0 -> 422
task_create
task_list
task_complete
task_complete missing task_id -> 422
asset_create_upload_url
asset_create_upload_url invalid asset_type -> 422
asset_register_external_url
capture_parse
capture_commit
capture_undo
capture_undo reused token -> 404
```

## Prerequisites

Start the local Lifly infrastructure and API before running the tests.

```bash
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

The tests assume the API is available at:

```text
http://localhost:8310
```

Override this with:

```bash
LIFLY_API_BASE_URL=http://localhost:8310
```

## Run

From `services/api`:

```bash
uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
```

Or from the repository root:

```bash
cd services/api
uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
```

## Expected result

```text
6 passed
```

## Notes

These tests create real local development rows in the configured database. They do not currently isolate each test in a disposable database transaction.

This is intentional for v0.1 because the goal is to guard the external MCP API contract. A later CI hardening task can introduce a dedicated test database and automated cleanup.
