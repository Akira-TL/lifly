#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-lifly}"
mkdir -p "$ROOT"
cd "$ROOT"
git init

mkdir -p apps services packages infra docs scripts .github/ISSUE_TEMPLATE
mkdir -p services/api services/cloud-mcp services/local-mcp services/worker
mkdir -p packages/protocol packages/domain packages/shared
mkdir -p infra/postgres infra/powersync infra/minio infra/redis

cat > package.json <<'JSON'
{
  "name": "lifly",
  "private": true,
  "packageManager": "pnpm@latest",
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "lint": "turbo lint",
    "test": "turbo test",
    "typecheck": "turbo typecheck",
    "dev:api": "cd services/api && uv run fastapi dev app/main.py",
    "dev:flutter:windows": "cd apps/client_flutter && flutter run -d windows",
    "analyze:flutter": "cd apps/client_flutter && flutter analyze"
  },
  "devDependencies": {
    "turbo": "latest",
    "typescript": "latest"
  }
}
JSON

cat > pnpm-workspace.yaml <<'YAML'
packages:
  - "services/cloud-mcp"
  - "services/local-mcp"
  - "packages/*"
YAML

cat > turbo.json <<'JSON'
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": { "dependsOn": ["^build"], "outputs": ["dist/**"] },
    "lint": { "outputs": [] },
    "test": { "outputs": [] },
    "typecheck": { "outputs": [] },
    "dev": { "cache": false, "persistent": true }
  }
}
JSON

echo "Monorepo skeleton created: $ROOT"
echo "Next: cd $ROOT && pnpm install"
echo "Then: docker compose -f infra/docker-compose.yml up -d"
echo "Flutter: cd apps && flutter create client_flutter --platforms=windows,android"
echo "FastAPI: cd services/api && uv init"
