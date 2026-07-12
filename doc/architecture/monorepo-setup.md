# Lifly Monorepo 搭建说明

## 1. 目标结构

```text
lifly/
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
├─ doc/
├─ scripts/
├─ .github/
├─ package.json
├─ pnpm-workspace.yaml
└─ turbo.json
```

## 2. 工具边界

TypeScript 服务与共享包使用 pnpm workspace。

Python/FastAPI 使用 uv。

Flutter 工程独立在 apps/client_flutter。

Docker Compose 管理 PostgreSQL、Redis、MinIO、PowerSync 等本地基础设施。

## 3. TypeScript 工作区

pnpm workspace 管理：

```text
services/cloud-mcp
services/local-mcp
packages/protocol
packages/domain
packages/shared
```

## 4. Python 服务

FastAPI 位于：

```text
services/api
```

worker 位于：

```text
services/worker
```

## 5. Flutter 客户端

客户端位于：

```text
apps/client_flutter
```

MVP 优先支持 Windows 与 Android。

## 6. AI agent 执行要求

AI agent 接任务前必须读取：

```text
doc/archive/v0.1.0plan/architecture-freeze.md
当前 Issue
相关模块文档
```

AI agent 只能修改 Issue 允许的文件范围，并在 PR 中说明验证方式。
