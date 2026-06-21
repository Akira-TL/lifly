# Seed GitHub Issues

## Create Milestones

```bash
gh milestone create "M0 Repo Bootstrap & Technical Spikes"
gh milestone create "M1 Local Data MVP"
gh milestone create "M2 Cloud Sync MVP"
gh milestone create "M3 Cloud MCP MVP"
gh milestone create "M4 Assets & Import MVP"
gh milestone create "M5 Windows Local MCP"
```

## Create M0 Issues

```bash
gh issue create --title "[LC-0001] Repo bootstrap" --label "type:infra,area:repo,agent:devops,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "创建 monorepo 基础结构，加入 docs、pnpm workspace、turbo、Flutter/FastAPI/MCP 服务目录。"

gh issue create --title "[LC-0002] Add docs v0.1 into repository" --label "type:docs,agent:docs,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "将开发文档包放入 docs/，并在 README 中链接关键文档。"

gh issue create --title "[LC-0003] FastAPI skeleton" --label "type:infra,area:backend,agent:backend,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "初始化 services/api，提供 health check。"

gh issue create --title "[LC-0004] Cloud MCP skeleton" --label "type:infra,area:mcp,agent:mcp,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "初始化 services/cloud-mcp，提供基础 MCP server 和 tool list。"

gh issue create --title "[LC-0005] Flutter client skeleton" --label "type:infra,area:client,agent:client,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "初始化 apps/client_flutter，支持 Windows 和 Android 构建。"

gh issue create --title "[LC-0006] Docker Compose local infra" --label "type:infra,area:devops,agent:devops,priority:p0,status:ready" --milestone "M0 Repo Bootstrap & Technical Spikes" --body "提供 PostgreSQL、Redis、MinIO、PowerSync 的本地开发配置。"
```
