# Lifly 开发文档总览

> 状态：正式文档入口。临时开发计划、已完成阶段记录和 release gate 流水不再作为长期入口维护。

Lifly 是一个 AI-first / Chat-first 的个人生活数据系统，以备忘、记账、任务提醒为最小闭环，以 MCP 服务为 AI 接入边界，以本地优先 + 云端同步为数据策略。

## 1. 文档维护原则

固定内容进入固定文档：

```text
产品定义和需求 -> 01 / 02
总体架构 -> 03
领域和数据模型 -> 05 / 06
同步与离线 -> 07
AI / MCP -> 08 / 09
客户端和导航 -> 10 / 22
服务端 API -> 11
业务模块 -> 12 到 18
DevOps 与提交规则 -> 20
测试质量 -> 21
路线图 -> 24
AI Agent 执行模型 -> 25
```

不再继续扩展临时开发计划文档。已经完成的开发计划、阶段执行记录、release gate 流水，在关键信息迁移到正式文档后可以删除。

## 2. 正式文档入口

```text
00-decision-record.md
01-product-definition.md
02-mvp-scope.md
03-architecture-overview.md
04-tech-stack.md
05-domain-model.md
06-data-model.md
07-sync-and-offline.md
08-mcp-design.md
09-ai-interaction-design.md
10-client-app.md
11-backend-api.md
12-asset-system.md
13-memo-doc-system.md
14-ledger-system.md
15-task-reminder-system.md
16-import-export.md
17-auth-security-privacy.md
18-audit-trash.md
19-local-mcp-desktop.md
20-devops-deployment.md
21-testing-quality.md
22-ui-information-architecture.md
23-open-source-commercial.md
24-roadmap.md
25-ai-execution-model.md
26-v0.1-architecture-freeze.md
27-milestones.md
28-issues-backlog.md
29-ai-role-boundaries.md
30-monorepo-setup.md
31-agent-task-protocol.md
32-pr-review-protocol.md
33-github-gitlab-project-setup.md
34-architecture-decision-record-template.md
99-glossary.md
```

## 3. 当前产品重点

```text
首页 Home Overview read model
记账预算、分类统计、消费洞察
备忘 AI 自动分类、标签元数据
任务 AI 预警策略
AI Capture 聊天式体验
手机端 5 底部导航：首页 / 备忘 / AI / 记账 / 任务
```

归档位置：

```text
产品边界 -> 01-product-definition.md
数据模型 -> 06-data-model.md
AI Capture -> 09-ai-interaction-design.md
客户端和导航 -> 10-client-app.md、22-ui-information-architecture.md
API -> 11-backend-api.md
备忘分类 -> 13-memo-doc-system.md
记账预算和洞察 -> 14-ledger-system.md
任务预警 -> 15-task-reminder-system.md
路线 -> 24-roadmap.md
```

## 4. 开发原则

1. App 不是唯一入口，AI/MCP 和客户端都可以记录。
2. 所有 AI 写入都走 MCP/API，不直接操作数据库。
3. 所有写入都有审计记录，可追踪、可撤销。
4. 本地优先，云端同步。
5. 附件独立于结构化同步。
6. 客户端不写死产品规则。预算、分类占比、消费洞察、AI 分类状态、任务预警策略必须来自正式数据契约。
