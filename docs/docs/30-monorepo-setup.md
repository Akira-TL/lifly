# 30. Monorepo 搭建说明

## 1. 目标结构

```text
lifecore/
├─ apps/
│  └─ client_flutter/
├─ services/
│  ├─ api/
│  ├─ cloud-mcp/
│  ├─ local-mcp/
│  └─ worker/
├─ packages/
│  ├─ protocol/
│  ├─ domain/
│  └─ shared/
├─ infra/
│  ├─ docker-compose.yml
│  ├─ powersync/
│  ├─ postgres/
│  ├─ minio/
│  └─ redis/
├─ docs/
├─ scripts/
├─ .github/
├─ package.json
├─ pnpm-workspace.yaml
├─ turbo.json
└─ README.md
```

## 2. 工具选择

- TypeScript 服务和共享包：pnpm workspace + Turborepo。
- Python/FastAPI：uv。
- Flutter：独立放在 apps/client_flutter。
- 基础设施：Docker Compose。

## 3. 初始化命令

```bash
mkdir lifecore
cd lifecore
git init

mkdir -p apps services packages infra docs scripts .github/ISSUE_TEMPLATE
mkdir -p services/api services/cloud-mcp services/local-mcp services/worker
mkdir -p packages/protocol packages/domain packages/shared
mkdir -p infra/postgres infra/powersync infra/minio infra/redis
```

## 4. pnpm workspace

`package.json`：

```json
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
```

`pnpm-workspace.yaml`：

```yaml
packages:
  - "services/cloud-mcp"
  - "services/local-mcp"
  - "packages/*"
```

## 5. 初始化子项目

```bash
# TypeScript packages
cd packages/protocol && pnpm init
cd ../domain && pnpm init
cd ../shared && pnpm init

# MCP services
cd ../../services/cloud-mcp && pnpm init
pnpm add zod
pnpm add -D typescript tsx @types/node

cd ../local-mcp && pnpm init
pnpm add zod
pnpm add -D typescript tsx @types/node

# FastAPI
cd ../api
uv init
uv add fastapi uvicorn sqlalchemy alembic pydantic pydantic-settings asyncpg psycopg[binary]

# Flutter
cd ../../apps
flutter create client_flutter --platforms=windows,android
```

## 6. 不建议的结构

不要：

- 把 Flutter 放进 pnpm package 管理；
- 把 Python API 强行放进 turbo build；
- 让 Local MCP 直接写 SQLite；
- 把 docs 放在仓库外。
