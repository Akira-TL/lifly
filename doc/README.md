# Lifly 文档总览

Lifly 文档按用途分层，不再使用数字前缀区分文档。固定内容进入固定目录，临时计划和阶段流水进入 archive 或删除。

## 目录结构

```text
doc/
├─ api/              接口契约、MCP 契约、OpenAPI 产物
├─ architecture/     架构、数据模型、同步、技术栈、ADR 模板
├─ archive/          历史冻结、旧计划、评审记录、决策摘要
├─ design/           客户端、UI 信息架构、AI 交互、角色边界
├─ guide/            开发指南、路线图、当前状态、任务池、测试质量
├─ legal/            安全隐私、开源商业化、隐私政策、用户协议
└─ requirements/     产品需求、MVP 范围、业务模块需求
```

## 当前产品重点

```text
首页 Home Overview read model
记账预算、分类统计、消费洞察
备忘 AI 自动分类、标签元数据
任务 AI 预警策略
AI Capture 聊天式体验
手机端 5 底部导航：首页 / 备忘 / AI / 记账 / 任务
```

## 常用入口

```text
requirements/product-definition.md
requirements/mvp-scope.md
architecture/architecture-overview.md
architecture/data-model.md
api/api-contract.md
design/client-app.md
design/ui-information-architecture.md
guide/development.md
guide/current-status.md
guide/roadmap.md
```

## 维护规则

1. 产品需求进入 `requirements/`。
2. API 契约进入 `api/`。
3. 技术架构和数据模型进入 `architecture/`。
4. 客户端交互、页面、导航进入 `design/`。
5. 开发、测试、路线、状态进入 `guide/`。
6. 安全、隐私、协议、商业化进入 `legal/`。
7. 旧计划、旧冻结、历史评审进入 `archive/`。
8. 不再新增数字前缀文档名。
