# API 索引

当前服务端 API 统一挂载在 `/api/v1` 下。

## Public API

```text
/api/v1/auth
/api/v1/memos
/api/v1/ledger
/api/v1/tasks
/api/v1/assets
/api/v1/imexport
/api/v1/search
/api/v1/dashboard
/api/v1/sync
/api/v1/audit
/api/v1/trash
/api/v1/plugins
/api/v1/robots
```

## MCP API

```text
/api/v1/mcp/capture/parse
/api/v1/mcp/capture/commit
/api/v1/mcp/capture/undo
/api/v1/mcp/memo/create
/api/v1/mcp/memo/search
/api/v1/mcp/expense/create
/api/v1/mcp/expense/search
/api/v1/mcp/expense/summary
/api/v1/mcp/task/create
/api/v1/mcp/task/list
/api/v1/mcp/task/complete
/api/v1/mcp/asset/create-upload-url
/api/v1/mcp/asset/register-external-url
```

详细字段和下一阶段契约见：

```text
api-contract.md
mcp-contract.md
```
