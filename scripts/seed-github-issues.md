# Seed GitHub Issues

本文档用于初始化 Lifly v0.1 的 GitHub Issues 和 Milestones。

建议先运行：

```bash
./scripts/create-github-labels.sh Akira-TL/lifly
```

## 1. Create Milestones

```bash
gh milestone create "M0 Repo Bootstrap & Technical Spikes"
gh milestone create "M1 Local Data MVP"
gh milestone create "M2 Cloud Sync MVP"
gh milestone create "M3 Cloud MCP MVP"
gh milestone create "M4 Assets & Import MVP"
gh milestone create "M5 Windows Local MCP"
```

## 2. Create M0 Issues

### LC-0001 Repo bootstrap verification

```bash
gh issue create \
  --title "[LC-0001] Verify M0 repo bootstrap and local dev startup" \
  --label "type:spike,area:repo,area:devops,agent:devops,priority:p0,status:ready,needs-local-validation" \
  --milestone "M0 Repo Bootstrap & Technical Spikes" \
  --body "$(cat <<'EOF'
Goal:
Verify that the current Lifly monorepo can be installed and started locally.

Context:
This is a local validation task. The GitHub connector cannot run pnpm/docker/uv/flutter commands.

Scope:
- Validate package manager setup
- Validate docker compose config
- Validate API startup
- Validate current docs and repo structure

Allowed Files / Directories:
- No code changes unless a failure is found
- If fixes are required, create a separate branch and PR

Forbidden Changes:
- Do not add new product features
- Do not change architecture freeze items
- Do not change database schema unless required to fix startup

Acceptance Criteria:
- pnpm install succeeds
- docker compose -f infra/docker-compose.yml config succeeds
- API health endpoint works locally
- Any failure is documented as follow-up issue

Validation:
- pnpm install
- docker compose -f infra/docker-compose.yml config
- docker compose -f infra/docker-compose.yml up -d
- cd services/api && uv run uvicorn app.main:app --reload --port 8210
- curl http://localhost:8210/api/v1/health

Related Docs:
- doc/archive/v0.1.0plan/architecture-freeze.md
- doc/architecture/monorepo-setup.md
- doc/guide/agent-task-protocol.md
EOF
)"
```

### LC-0002 Architecture audit

```bash
gh issue create \
  --title "[LC-0002] Audit current code against Lifly v0.1 architecture freeze" \
  --label "type:docs,area:repo,agent:architect,priority:p0,status:ready" \
  --milestone "M0 Repo Bootstrap & Technical Spikes" \
  --body "$(cat <<'EOF'
Goal:
Compare current code with Lifly v0.1 architecture freeze and document gaps.

Context:
The repository already has FastAPI modules, SQLAlchemy models, MCP routing, docker compose, and workspace files. We need a code-vs-doc audit before adding more features.

Scope:
- Inspect services/api/app/main.py
- Inspect services/api/app/db/models.py
- Inspect services/api/app/modules/**
- Inspect infra/docker-compose.yml
- Inspect package.json and pnpm-workspace.yaml
- Write doc/archive/reviews/current-architecture-audit.md

Allowed Files / Directories:
- doc/archive/reviews/current-architecture-audit.md
- README.md only if doc index needs update

Forbidden Changes:
- Do not change runtime code in this audit issue
- Do not add new product features
- Do not change architecture freeze

Acceptance Criteria:
- Audit document lists aligned items
- Audit document lists gaps
- Audit document lists recommended next issues
- No runtime code changes

Validation:
- Documentation review

Related Docs:
- doc/archive/v0.1.0plan/architecture-freeze.md
- doc/architecture/data-model.md
- doc/api/mcp-contract.md
- doc/guide/agent-task-protocol.md
EOF
)"
```

### LC-0003 MCP tool schema v0.1

```bash
gh issue create \
  --title "[LC-0003] Define Lifly MCP tool schema v0.1" \
  --label "type:feature,area:mcp,area:protocol,agent:mcp,priority:p0,status:ready" \
  --milestone "M0 Repo Bootstrap & Technical Spikes" \
  --body "$(cat <<'EOF'
Goal:
Define the first stable MCP tool schema package for Lifly.

Context:
MCP is the AI boundary. Tool schemas must be stable before implementing individual tool handlers.

Scope:
- Define schemas for capture_parse, capture_commit, capture_undo
- Define schemas for memo_create, memo_search
- Define schemas for expense_create, expense_search, expense_summary
- Define schemas for task_create, task_list, task_complete
- Define schemas for asset_create_upload_url, asset_register_external_url

Allowed Files / Directories:
- packages/protocol/**
- services/cloud-mcp/** only if needed for imports
- doc/api/mcp-contract.md only if schema details need alignment

Forbidden Changes:
- Do not implement business persistence in this issue
- Do not add tools outside architecture freeze
- Do not call database directly from MCP

Acceptance Criteria:
- Schema package exports all v0.1 tool schemas
- Schema tests exist
- Tool names match doc/archive/v0.1.0plan/architecture-freeze.md

Validation:
- pnpm --filter @lifly/protocol test
- pnpm typecheck

Related Docs:
- doc/api/mcp-contract.md
- doc/archive/v0.1.0plan/architecture-freeze.md
EOF
)"
```

## 3. Create M1 Issues after M0 is green

Only create M1 issues after LC-0001 and LC-0002 are complete.

Suggested next issues:

```text
[LC-0101] Define initial database migration alignment
[LC-0102] Implement memo local CRUD validation path
[LC-0103] Implement ledger transaction CRUD validation path
[LC-0104] Implement task CRUD validation path
```

## 4. AI Agent Prompt Template

Use this when assigning an issue to an AI agent:

```text
You are the Lifly <ROLE> Agent.
Read first:
- doc/archive/v0.1.0plan/architecture-freeze.md
- doc/guide/agent-task-protocol.md
- current Issue
- related doc files listed in the Issue

Execute only this Issue.
Do not expand scope.
Do not change architecture freeze items.
Return output as:
Summary / Changed Files / Validation / Risks / Follow-ups.
```
