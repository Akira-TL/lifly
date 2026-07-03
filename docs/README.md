# Lifly 开发文档总览

> 版本：v0.4.11 release
> 日期：2026-07-03
> 状态：AI Write 全量开发已收口，下一阶段进入 v0.5 Assets & Import/Export

Lifly 是一个 AI-first / Chat-first 的个人生活数据系统。它不是传统意义上的日程 App、记账 App 或备忘录 App，而是一个以 **备忘录、记账、任务提醒** 为最小闭环，以 **MCP 服务** 为 AI 接入边界，以 **本地优先 + 云端同步** 为数据策略的个人生活数据基础设施。

## 目录结构

```text
docs/
├─ 00-decision-record.md              # 当前已确认决策
├─ 01-product-definition.md           # 产品定义与范围
├─ 02-mvp-scope.md                    # MVP 范围与阶段计划
├─ 03-architecture-overview.md        # 总体架构
├─ 04-tech-stack.md                   # 技术选型
├─ 05-domain-model.md                 # 领域模型
├─ 06-data-model.md                   # 数据库设计
├─ 07-sync-and-offline.md             # 本地优先与同步设计
├─ 08-mcp-design.md                   # MCP 服务设计
├─ 09-ai-interaction-design.md        # AI 交互与混合输入解析
├─ 10-client-app.md                   # Flutter 客户端设计
├─ 11-backend-api.md                  # 后端 API 与服务设计
├─ 12-asset-system.md                 # 附件与对象存储设计
├─ 13-memo-doc-system.md              # 备忘录/文档系统
├─ 14-ledger-system.md                # 记账系统
├─ 15-task-reminder-system.md         # 任务提醒系统
├─ 16-import-export.md                # 导入导出
├─ 17-auth-security-privacy.md        # 认证、安全与隐私
├─ 18-audit-trash.md                  # 审计、回收站与删除策略
├─ 19-local-mcp-desktop.md            # Windows 本地 MCP
├─ 20-devops-deployment.md            # 部署、环境与 DevOps
├─ 21-testing-quality.md              # 测试与质量保障
├─ 22-ui-information-architecture.md  # 页面与信息架构
├─ 23-open-source-commercial.md       # 开源与商业化策略
├─ 24-roadmap.md                      # 路线图
├─ 59-version-control-plan.md         # 版本控制与后续开发计划
├─ 60-major-version-roadmap.md        # 大版本开发路线图
├─ 62-local-core-persistence-regression.md # Local Core 持久化回归验证
├─ 63-v0.2-release-gate.md            # v0.2 发布门禁结果
├─ development-plans/v0.4.0-ai-write-full-development.md # v0.4 AI 写入收口记录
├─ development-plans/v0.5.0-assets-import-export-mvp.md # v0.5 附件导入导出计划
└─ 99-glossary.md                     # 术语表
```

## 开发原则

1. **App 不是唯一入口**：用户可以在 App 内手动记录，也可以通过 AI/MCP、Hermes、OpenClaw、机器人等入口记录。
2. **所有 AI 写入都走 MCP/API**：AI 不直接操作数据库。
3. **所有写入都有审计记录**：新增、修改、删除、导入都必须可追踪、可撤销。
4. **本地优先，云端同步**：Windows 和 Android 客户端离线也能手动记录。
5. **云端 MCP 优先，本地 MCP 兜底**：普通场景走云端 MCP；Windows 桌面端支持本地 MCP，用于本地模型、离线 AI、私有部署。
6. **附件独立于结构化同步**：文本和元数据走数据库同步，文件二进制走对象存储和本地缓存。
7. **MVP 聚焦三件事**：备忘录、记账、任务提醒。
