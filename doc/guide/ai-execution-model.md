# AI 执行模型

## 1. 核心原则

Lifly 的开发执行者主要是 AI agent，因此项目管理不能依赖人类口头沟通、会议同步和隐性上下文。所有执行依据必须进入仓库中的正式文档、Issue、PR 描述和代码。

AI agent 开始任务前必须读取：

```text
CLAUDE.md
/home/Akira/.claude/CLAUDE.md
相关模块正式设计文档
当前 Issue 或用户明确需求
```

## 2. Issue 是任务合同

每个 Issue 必须包含：

```text
Goal
Context
Scope
Allowed files
Forbidden changes
Acceptance criteria
Validation
Related docs
```

Issue 没写的内容默认不做。若用户在对话中直接授权开发，该对话中的明确需求等同于本轮任务合同。

## 3. PR / Commit 是交付单元

每个 PR 或本地提交必须说明：

```text
完成了什么
改了哪些平台：服务端 / Flutter 客户端 / 桌面端 / 手机端 / 文档
如何验证
是否影响架构冻结项
是否新增依赖
是否更新正式文档
```

提交信息使用：

```text
feat(module): 中文描述
fix(module): 中文描述
```

## 4. AI 角色

```text
Architect Agent       架构维护与边界控制
Client Agent          Flutter 客户端
Backend Agent         FastAPI / PostgreSQL / PowerSync
MCP Agent             Cloud MCP / Local MCP
Sync Agent            同步与离线
Asset Agent           附件与对象存储
Import Agent          CSV 导入导出
QA Agent              测试与验收
DevOps Agent          Monorepo / CI / Docker
Docs Agent            文档同步与变更整理
```

## 5. 禁止行为

AI agent 禁止：

- 私自新增产品模块；
- 绕过 MCP/API 直接让 AI 写数据库；
- 让导入流程直接写正式账单表而不经过预览和确认；
- 把附件二进制写进 PostgreSQL；
- 把 Local MCP 设计成 Android 服务；
- 删除 audit log；
- 物理删除用户数据而不走回收站/tombstone；
- 修改架构冻结项而不更新正式文档或 ADR；
- 在客户端页面写死预算、分类占比、AI 分类状态、任务预警策略等产品规则。

## 6. 文档整理规则

固定内容必须进入固定正式文档：

```text
产品定义和需求：doc/requirements/product-definition.md、doc/requirements/mvp-scope.md
总体架构：doc/architecture/architecture-overview.md
领域和数据模型：doc/architecture/domain-model.md、doc/architecture/data-model.md
同步与离线：doc/architecture/sync-and-offline.md
AI/MCP：doc/api/mcp-contract.md、doc/design/ai-interaction.md
客户端：doc/design/client-app.md、doc/design/ui-information-architecture.md
服务端 API：doc/api/api-contract.md
业务模块：doc/requirements/asset-system.md、doc/requirements/memo-doc-system.md、doc/requirements/ledger-system.md、doc/requirements/task-reminder-system.md、doc/requirements/import-export.md、doc/requirements/audit-trash.md
DevOps 与版本规则：doc/guide/development.md
测试与质量：doc/guide/testing-quality.md
路线图：doc/guide/roadmap.md
```

临时开发计划、阶段执行记录、已经完成的 release gate 记录不再作为长期入口继续扩展。可迁移的结论应归入上面的正式文档，迁移后删除临时计划文档。
