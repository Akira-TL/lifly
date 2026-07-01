# 40. MCP Read Tools and Task Complete Hardening

Issue: `#26 [LC-0012] Harden MCP read tools and task_complete validation`

## Scope

This slice hardens the remaining MCP read/list/summary/complete tools.

Implemented:

```text
memo_search request validation
expense_search request validation
expense_summary request validation
task_list request validation
task_complete request validation
task_complete service reuse
normal task API complete service reuse
```

Not included:

```text
advanced search
semantic search
date range filters
frontend UI
auth changes
new MCP tools
```

## Runtime Changes

The following MCP tools now validate request bodies through Pydantic schemas:

```text
POST /api/v1/mcp/memo/search
POST /api/v1/mcp/expense/search
POST /api/v1/mcp/expense/summary
POST /api/v1/mcp/task/list
POST /api/v1/mcp/task/complete
```

Invalid `limit`, invalid `period`, invalid `task_status`, and missing `task_id` return `422`.

Task completion is now centralized in:

```text
services/api/app/modules/tasks/service.py
complete_task_record(...)
```

Both normal API and MCP use this path:

```text
POST /api/v1/tasks/{task_id}/complete
POST /api/v1/mcp/task/complete
```

The MCP path writes audit logs with:

```text
actor_type=ai
source_channel=mcp
tool_name=task_complete
```

## Validation Checklist

Start the API with:

```text
cd services/api
uv run uvicorn app.main:app --reload --port 8310
```

Then validate these cases manually with HTTP requests:

```text
1. POST /api/v1/mcp/memo/search with {} returns a memos array.
2. POST /api/v1/mcp/memo/search with {"limit":0} returns 422.
3. POST /api/v1/mcp/expense/search with {"q":"Coffee","limit":5} returns transactions array.
4. POST /api/v1/mcp/expense/summary with {"period":"current_month"} returns current month summary.
5. POST /api/v1/mcp/expense/summary with {"period":"all_time"} returns 422.
6. POST /api/v1/mcp/task/list with {"task_status":"todo","limit":10} returns tasks array.
7. POST /api/v1/mcp/task/list with {"task_status":"invalid"} returns 422.
8. Create a task through /api/v1/mcp/task/create, then complete it through /api/v1/mcp/task/complete.
9. POST /api/v1/mcp/task/complete with {} returns 422.
10. Create a task through /api/v1/tasks, then complete it through /api/v1/tasks/{task_id}/complete.
```

Expected completion behavior:

```text
task_status=done
completed_at is not null
normal API response keeps success=true
MCP response keeps {"task": ...}
```
