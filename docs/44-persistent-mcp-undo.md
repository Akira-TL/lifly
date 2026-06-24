# Lifly Persistent MCP Undo

Status: v0.1 implementation slice  
Issue: LC-0016

## Why this exists

MCP create tools return an `undo_token` so AI clients can immediately roll back accidental writes. The previous implementation stored undo actions in process memory. That was acceptable for early smoke testing, but it meant an API restart lost all pending undo tokens.

This slice moves undo actions into PostgreSQL while preserving the public MCP response shapes.

## Runtime table

`mcp_undo_actions` stores one row per entity action.

Important fields:

| Field | Meaning |
| --- | --- |
| `undo_token` | Public one-shot token returned by MCP create/commit endpoints. |
| `user_id` | Owner of the undo action. MVP uses `local-dev`. |
| `entity_type` | `memo`, `ledger_transaction`, or `task`. |
| `entity_id` | Entity to roll back. |
| `action` | Currently `create`. Future values may support update/delete rollback. |
| `status` | `pending` or `used`. |
| `expires_at` | Current default is 24 hours after token creation. |
| `used_at` | Set when `capture_undo` consumes the token. |

## Write path

Direct MCP create tools now write undo actions in the same database transaction as the entity creation:

```text
memo_create / expense_create / task_create
  -> create entity
  -> create mcp_undo_actions rows
  -> commit
  -> return undo_token
```

`capture_commit` does the same for every created entity:

```text
capture_commit
  -> create selected entities
  -> create one undo token
  -> create mcp_undo_actions rows for all created entities
  -> commit
  -> return undo_token
```

## Undo path

`capture_undo` now consumes pending database rows:

```text
capture_undo
  -> validate undo_token
  -> select pending non-expired mcp_undo_actions rows
  -> mark selected rows used
  -> mark target entities ai_trashed
  -> write audit_logs rows
  -> commit
```

A reused token returns `404` because the rows are no longer `pending`.

## Validation

Run the existing MCP smoke script:

```bash
bash scripts/smoke-mcp-v0.1.sh
```

Run the API integration test:

```bash
cd services/api
uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
```

Optional database check after creating an entity:

```bash
docker compose -f infra/docker-compose.yml exec postgres \
  psql -U lifly -d lifly -c "select undo_token, entity_type, entity_id, status, expires_at from mcp_undo_actions order by created_at desc limit 5;"
```

Expected behavior:

- Before undo, rows are `pending`.
- After undo, rows are `used` and `used_at` is populated.
- Reusing the same token returns `404`.
- Restarting the API process no longer loses pending undo tokens.

## Known limitations

This slice only supports rollback of create actions for memo, ledger transaction, and task entities. Asset undo and complex update/delete rollback remain out of scope for v0.1.
