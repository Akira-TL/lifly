# Lifly CI Basic Checks

Status: v0.1 CI baseline
Issue: LC-0015
Workflow: `.github/workflows/ci.yml`

## Goal

This workflow adds the first automated CI gate for Lifly pull requests and `master` pushes.

It is intentionally small:

- protocol package contract checks;
- API MCP v0.1 integration tests;
- no deployment;
- no image publishing;
- no client build yet.

## Trigger

The workflow runs on:

- pull requests targeting `master`;
- pushes to `master`.

## Jobs

### `protocol`

Runs the TypeScript protocol package checks:

```bash
pnpm install --no-frozen-lockfile
pnpm --filter @lifly/protocol test
pnpm --filter @lifly/protocol typecheck
```

This protects MCP tool schema contracts in `packages/protocol`.

### `api`

Starts Lifly local infrastructure with Docker Compose:

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis minio
```

Then installs API dependencies and starts the FastAPI server on port `8310`:

```bash
cd services/api
uv sync --group dev
uv run uvicorn app.main:app --host 127.0.0.1 --port 8310
```

After `/api/v1/health` is reachable, it runs:

```bash
cd services/api
LIFLY_API_BASE_URL=http://127.0.0.1:8310 \
  uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
```

This protects the current MCP v0.1 contract:

- health version;
- memo create/search validation;
- expense create/search/summary validation;
- task create/list/complete validation;
- asset upload URL/external URL validation;
- capture parse/commit/undo validation.

## Local equivalent

From repository root:

```bash
docker compose -f infra/docker-compose.yml up -d postgres redis minio
```

Terminal 1:

```bash
cd services/api
uv sync --group dev
uv run uvicorn app.main:app --host 127.0.0.1 --port 8310
```

Terminal 2:

```bash
pnpm install --no-frozen-lockfile
pnpm --filter @lifly/protocol test
pnpm --filter @lifly/protocol typecheck

cd services/api
LIFLY_API_BASE_URL=http://127.0.0.1:8310 \
  uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
```

## Current limitations

This CI does not yet cover:

- Flutter client analysis/build;
- full Docker image build;
- PowerSync profile;
- cloud deployment;
- browser/mobile E2E tests;
- persistent undo storage.

Those should be added as separate slices after the MCP/API baseline stabilizes.
