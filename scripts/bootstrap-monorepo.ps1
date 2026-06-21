param([string]$Root = "lifecore")
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Set-Location $Root
git init

$dirs = @(
  "apps", "services/api", "services/cloud-mcp", "services/local-mcp", "services/worker",
  "packages/protocol", "packages/domain", "packages/shared",
  "infra/postgres", "infra/powersync", "infra/minio", "infra/redis",
  "docs", "scripts", ".github/ISSUE_TEMPLATE"
)
foreach ($dir in $dirs) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

@'
{
  "name": "lifecore",
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
'@ | Set-Content -Encoding UTF8 package.json

@'
packages:
  - "services/cloud-mcp"
  - "services/local-mcp"
  - "packages/*"
'@ | Set-Content -Encoding UTF8 pnpm-workspace.yaml

@'
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
'@ | Set-Content -Encoding UTF8 turbo.json

Write-Host "Monorepo skeleton created: $Root"
Write-Host "Next: cd $Root; pnpm install"
Write-Host "Then: docker compose -f infra/docker-compose.yml up -d"
Write-Host "Flutter: cd apps; flutter create client_flutter --platforms=windows,android"
Write-Host "FastAPI: cd services/api; uv init"
