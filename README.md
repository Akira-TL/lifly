# LifeCore

AI-first / Chat-first personal life data system.

## Docs

Start here:

```text
docs/00-decision-record.md
docs/26-v0.1-architecture-freeze.md
docs/27-milestones.md
docs/28-issues-backlog.md
docs/30-monorepo-setup.md
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
