# Lifly Issues Backlog

本文档只保留 Issue 种子和长期任务池，不再链接临时开发计划文档。已完成版本的实现细节以代码和正式模块文档为准。

## 1. 已完成能力族

```text
v0.1 Foundation / Governance
v0.2 Local Data
v0.3 Cloud Sync
v0.4 AI Write / MCP
v0.5 Assets & Import / Export
v0.6 Import / Export / Asset Experience
```

已完成能力包括：

```text
备忘 / 记账 / 任务 CRUD
本地数据和同步基础
Cloud MCP / Local MCP
capture_parse / capture_commit / capture_undo
审计 / 回收站 / 撤销
附件 metadata / 上传意图 / 外链注册
通用 CSV / 支付宝 / 微信账单导入
导入预览 / 提交 / 回滚
导出基础能力
Flutter 真实 API 接入和导入导出体验层
```

## 2. 当前任务池：客户端体验与手机端产品地基

### LC-0701 Local Home Overview read model

状态：云端 /api/v1/home/overview 与本地 fallback 基础链路已完成，预算进度、分类占比和财务洞察字段已扩展，完整状态摘要待补。

目标：新增云端同步优先、本地失败兜底的产品化首页 read model，支撑今日关注、紧急事项、混合最近内容流和数据状态摘要。

验收：

```text
LocalCoreBridge.getHomeOverview 可基于本地 PowerSync 数据返回 schema_version、source_mode、attention_items、today_metrics、finance_overview、recent_activity 等结构
HomeOverviewRepository 已接入云端优先读取，失败后 Local Core fallback
HomePage 已改为消费 HomeOverview repository
/api/v1/home/overview 已提供云端正常读取入口
/dashboard 保留兼容
Local Core tests 覆盖主要聚合规则
Flutter repository/entity 可消费同构真实字段
云端失败或断网时首页仍可展示已有本地概览
```

### LC-0702 Ledger budgets and category aggregation

状态：基础链路已完成，本地月份 period 聚合已修正，预算 CRUD、分类预算、月环比和更细洞察待补。

目标：补齐预算、分类占比、月环比和消费洞察地基。

验收：

```text
ledger_budgets 模型明确
PowerSync ledger_budgets schema 已接入
Local Core ledger overview/category summary/insights 可本地计算
云端 ledger overview/category summary/insights 接口已提供正常读取入口
LedgerRepository 支持云端优先、失败后本地 fallback
没有预算时返回 not_configured，而不是客户端假造默认预算
```

### LC-0703 Memo AI classifications and tag metadata

状态：基础链路已完成，自动建议生成和 tag_metadata 管理 API 已补齐，备忘页 UI 消费待补。

目标：补齐备忘 AI 自动分类、分类置信度、用户确认状态和标签元数据。

验收：

```text
memo_classifications 模型明确
tag_metadata 模型明确
PowerSync memo_classifications / tag_metadata schema 已接入
Local Core 分类读取、确认、拒绝、标签统计可本地计算
云端分类接口、分类生成接口、标签统计接口和标签元数据管理接口已提供正常读取入口
rejected 分类不进入标签统计
客户端不根据字符串猜测 AI 已分类状态
备忘创建/更新会触发本地与云端同构的 AI 分类建议生成
```

### LC-0704 Task reminder strategies

状态：基础链路已完成，AI 预警策略生成器和 Reminder 表落地写入已补齐，UI 消费待补。

目标：补齐任务预警策略、AI 提醒建议、提前准备窗口和用户确认状态。

验收：

```text
task_reminder_strategies 模型明确
PowerSync task_reminder_strategies schema 已接入
本地任务列表 read model 可输出 urgent / warning / today 分组
云端任务策略接口已提供正常读取入口
没有策略时返回 null，不伪造 AI 预警
策略确认后才更新 Task.remind_at
策略确认后写入 reminders pending 记录
任务创建/更新会触发本地与云端同构的策略建议生成
```

### LC-0705 Mobile five-tab shell

状态：基础链路已完成，首页数据状态卡片跳转和桌面端更多管理入口待补。

目标：手机端底部导航收敛为：首页 / 备忘 / AI / 记账 / 任务。

验收：

```text
AppShell 手机端底部入口已固定为：首页 / 备忘 / AI / 记账 / 任务
AI 已作为居中主按钮入口
搜索和设置已退出手机端底部一级入口
首页顶部已提供全局搜索和设置入口
宽屏 Flutter 已使用 NavigationRail 作为非手机布局基础
widget test 已覆盖核心入口切换和底部入口收敛
```

### LC-0706 Chat-style AI Capture

状态：基础链路已完成，本地 capture_parse 已具备最小规则拆分，聊天式多轮 UI、asset_ids 真实解析、STT 和会话恢复体验待补。

目标：在现有 parse / commit / undo 基础上升级聊天式捕获体验，并保证 capture session、turns、确认结果和撤销链路可本地持久化。

验收：

```text
服务端 McpCaptureSession 已增强 session_status / committed_at / dismissed_at
服务端 McpCaptureTurn 已落地，parse / commit / undo 会写入 turn
PowerSync mcp_capture_sessions / mcp_capture_turns schema 已接入
PowerSyncCaptureStore 可本地持久化 captureParse / captureCommit / captureUndo
本地 commit 创建实体时写入 source_capture_id
本地 undo 使用 mcp_undo_actions 并将实体转为 ai_trashed
AiCaptureService local mode 可走 Local Core
PowerSync capture store test 覆盖 session / turn / commit / undo 链路
本地 capture_parse 最小规则拆分覆盖 task_create / expense_create 候选动作
```

### LC-0707 Product foundation release gate

目标：确认 v0.7 产品地基没有假数据和客户端硬编码产品规则。
