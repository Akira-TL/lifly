# Lifly

AI-first / Chat-first personal life data system.

Current stable development tag: `v0.4.11`.

Next development entry: `v0.5.0` Assets & Import/Export.

## Docs

Start here:

```text
docs/00-decision-record.md
docs/26-v0.1-architecture-freeze.md
docs/27-milestones.md
docs/28-issues-backlog.md
docs/30-monorepo-setup.md
docs/31-agent-task-protocol.md
docs/32-pr-review-protocol.md
docs/33-github-gitlab-project-setup.md
docs/34-architecture-decision-record-template.md
docs/59-version-control-plan.md
docs/60-major-version-roadmap.md
docs/development-plans/v0.4.0-ai-write-full-development.md
docs/development-plans/v0.5.0-assets-import-export-mvp.md
```

## Quick Start

```bash
pnpm install
docker compose -f infra/docker-compose.yml up -d
pnpm dev
```

## Structure

```text
apps/client_flutter
services/api
services/cloud-mcp
services/local-mcp
services/worker
packages/protocol
packages/domain
packages/shared
infra
docs
```

## AI Agent Rule

Before editing code, every AI agent must read:

```text
docs/26-v0.1-architecture-freeze.md
current GitHub Issue
related module docs
```

The Issue is the task contract. Do not expand scope beyond the Issue.
