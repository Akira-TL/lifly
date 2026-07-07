# Lifly Milestones

本文档只保留里程碑状态，不承载单轮开发计划。具体能力定义以正式模块文档为准。

## M0：Repo Bootstrap & Governance Alignment

状态：已完成。

目标：完成仓库命名、文档入仓、AI 执行规范、基础工程结构和本地开发设施对齐。

## M1：Local Data MVP

状态：已完成。

目标：完成客户端本地手动记录闭环。

范围：

```text
memo CRUD
expense CRUD
task CRUD
本地 SQLite / PowerSync schema
基础 UI
```

## M2：Cloud Sync MVP

状态：已完成。

目标：完成云同步闭环。

范围：

```text
登录
PostgreSQL schema
PowerSync 集成
跨端同步
audit_logs
trash 状态机
```

## M3：AI Write / MCP

状态：已完成。

目标：AI/MCP 写入、确认、撤销、审计和诊断形成完整闭环。

范围：

```text
Cloud MCP / Local MCP 共用 tool schema
capture_parse / capture_commit / capture_undo
AI undo 进入 ai_trashed，不物理删除
Flutter AI 写入入口
AI 写入审计摘要
Cloud / Local MCP parity tests
```

## M4：Assets & Import / Export

状态：已完成。

目标：附件与 CSV 导入导出闭环。

范围：

```text
asset_create_upload_url
asset_register_external_url
memo asset 引用
微信 / 支付宝账单导入预览
导入提交与批次回滚
Markdown / CSV / JSON export
```

## M5：Import / Export / Asset Experience

状态：已完成。

目标：把附件、导入、回滚和导出 API 闭环做成 Flutter 客户端可用体验。

范围：

```text
Flutter 导入入口与文件选择
微信 / 支付宝账单预览表格
导入提交与二次确认
导入批次列表与回滚
导出入口与诊断信息
附件库基础管理体验
```

## M6：Client Experience & Mobile Product Foundation

状态：当前阶段。

目标：补齐手机端真实产品页面需要的云端同步优先、本地可兜底的数据地基，再做真实 UI 消费。

范围：

```text
Local Home Overview read model
Local Ledger budgets / category aggregation / insights
Local Memo AI classifications / tag metadata
Local Task reminder strategies
Local Chat-style AI Capture
手机端 5 底部导航：首页 / 备忘 / AI / 记账 / 任务
```

当前进展：

```text
Home Overview 基础链路已落地：服务端 /api/v1/home/overview、LocalCoreBridge.getHomeOverview、LocalHomeOverviewBuilder、HomeOverviewRepository 云端优先/失败 fallback、HomePage repository 消费、云端/本地混合最近活动流
Ledger budgets 与分类聚合基础链路已落地：LedgerBudget、PowerSync ledger_budgets schema、/ledger/overview、/ledger/categories/summary、/ledger/insights、LedgerRepository 云端优先/失败 fallback
Memo AI 分类与标签元数据基础链路已落地：MemoClassification、TagMetadata、PowerSync memo_classifications/tag_metadata schema、备忘分类确认/拒绝接口、/tags/summary、MemoRepository 分类与标签统计
Task reminder strategies 基础链路已落地：TaskReminderStrategy、PowerSync task_reminder_strategies schema、任务分组 group、策略读取/确认/dismiss 接口、TaskRepository 策略读写
手机端 5 底部导航 Shell 基础链路已落地：AppShell 收敛为首页 / 备忘 / AI / 记账 / 任务，AI 为居中主按钮，搜索/设置降级到首页入口，宽屏 Flutter 使用 NavigationRail
Local Chat-style AI Capture 基础链路已落地：McpCaptureSession / McpCaptureTurn、PowerSync mcp_capture_sessions / mcp_capture_turns、PowerSyncCaptureStore、LocalCoreBridge.captureParse/Commit/Undo、AiCaptureService 本地模式接入、commit/undo turn 持久化
```

验收：

```text
首页、预算、分类、洞察、AI 分类、任务预警正常优先来自云端拉取和同步，云端失败或断网时来自 Local Core / PowerSync 本地 read model
云端 API 与本地 read model 字段同构，云端负责正常拉取和同步，本地负责失败兜底和离线可用
客户端不写假数据、不硬编码长期产品规则
手机端、Web、桌面端共享业务语义但可以使用不同布局
```

## M7：Desktop Local MCP & Production Hardening

状态：后续。

目标：强化桌面端 Local MCP、本地模型、离线 AI、发布包和生产稳定性。

范围：

```text
Local MCP stdio
Desktop Local Core host transport
与 Cloud MCP 共用 schema
发布包与升级策略
生产监控与错误反馈
隐私政策和用户协议
```
