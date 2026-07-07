# Lifly

AI-first / Chat-first personal life data system.

Lifly 以备忘、记账、任务提醒为最小闭环，以 MCP/API 为 AI 写入边界，以本地优先 + 云端同步为数据策略。

## Current Focus

```text
客户端体验与手机端产品地基
首页 Home Overview read model
记账预算、分类统计、消费洞察
备忘 AI 自动分类、标签元数据
任务 AI 预警策略
AI Capture 聊天式体验
手机端 5 底部导航：首页 / 备忘 / AI / 记账 / 任务
```

## Docs

正式文档入口：

```text
docs/README.md
```

常用文档：

```text
docs/01-product-definition.md
docs/03-architecture-overview.md
docs/06-data-model.md
docs/09-ai-interaction-design.md
docs/10-client-app.md
docs/11-backend-api.md
docs/13-memo-doc-system.md
docs/14-ledger-system.md
docs/15-task-reminder-system.md
docs/20-devops-deployment.md
docs/22-ui-information-architecture.md
docs/24-roadmap.md
docs/25-ai-execution-model.md
```

临时开发计划和已完成阶段记录不再作为长期文档入口维护。固定内容应迁移到上面的正式文档。

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
CLAUDE.md
/home/Akira/.claude/CLAUDE.md
related module docs
current Issue or user request
```

The Issue or explicit user request is the task contract. Do not expand scope beyond it.
