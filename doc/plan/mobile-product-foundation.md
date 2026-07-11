# 手机端产品地基云端同步优先与本地兜底开发计划

## 计划状态

```text
状态：执行中
当前分支：develop/v0.7.0
平台范围：Flutter Local Core / 本地 SQLite / PowerSync schema / repository / 服务端同构 API / 手机端 UI / Web 与桌面端适配原则
当前动作：阶段六已完成聊天式 AI Capture 数据地基，后续进入产品地基 release gate
完成规则：计划内能力实现并回写固定正式文档后，删除本文档
```

## 背景判断

当前 Lifly 已具备核心底座：

```text
备忘
记账
任务
AI Capture parse / commit / undo
导入导出
审计
撤销
同步 schema
Flutter 真实 API 接入
Local Core bridge
PowerSync 本地数据基础
```

手机端新设计里出现的能力不只是 UI 外壳：

```text
今日关注
紧急提醒
预算进度
分类占比
AI 自动标签
AI 提醒策略
聊天式 AI 捕获
语音输入
混合最近内容流
数据与设置摘要
```

这些能力不能靠 Flutter 页面临时拼接。正常联网状态下，Lifly 应从云端拉取和同步最新数据；但云端拉取失败、断网或弱网时，这些能力必须能基于本地数据计算：

```text
本地 SQLite / PowerSync 数据
  ↓
Local Core read model / query service
  ↓
Flutter repository DTO / entity
  ↓
手机端页面展示
```

云端 API 是正常在线读取和跨设备同步入口；Local Core 是断网、弱网、云端失败时的同构兜底，避免手机端首页与统计能力被网络卡死。

## 固定文档复查结论

主要长期结论已经写入固定文档：

```text
产品边界：doc/requirements/product-definition.md
数据模型：doc/architecture/data-model.md
API 契约：doc/api/api-contract.md
AI Capture：doc/design/ai-interaction.md
客户端职责：doc/design/client-app.md
UI 信息架构：doc/design/ui-information-architecture.md
备忘分类：doc/requirements/memo-doc-system.md
记账预算与洞察：doc/requirements/ledger-system.md
任务预警：doc/requirements/task-reminder-system.md
路线和任务池：doc/guide/roadmap.md、doc/guide/pending-tasks.md
测试质量门槛：doc/guide/testing-quality.md
```

本计划新增一条更高优先级原则：

```text
所有概览、预算、分类、预警、最近内容流等产品化 read model，必须云端可拉取、同步后本地可计算，并支持云端失败时本地兜底。
```

## 核心原则

### 本地计算优先

主路径：

```text
Flutter UI
  ↓
Repository
  ↓
Local Core read model / query service
  ↓
PowerSync local database / SQLite
```

云端路径：

```text
Flutter UI
  ↓
Repository
  ↓
Cloud API，同构字段兜底
```

云端只允许作为：

```text
同步源
备份源
远程访问兜底
服务端校验
跨端一致性校验
AI 云端解析能力入口
```

云端不应该成为以下能力的唯一来源：

```text
首页今日关注
预算进度
分类占比
消费洞察
混合最近内容流
任务紧急预警
标签统计
同步与导入状态摘要
```

### 接口不能写死

客户端禁止长期写死：

```text
预算金额
预算进度
分类占比
分类颜色和图标
AI 已分类状态
任务提前几天提醒
消费环比洞察
首页 attention 排序
同步和导入健康状态
```

这些内容必须来自统一契约：

```text
Local Core read model
PowerSync 同步 schema
repository DTO / entity
Cloud API 同构响应
```

### Read model 必须同构

本地 read model 和云端 API 必须返回同构结构，至少包括：

```text
schema_version
generated_at
user_timezone
source_mode: local / api / fallback
```

同构的意义是：

```text
手机端离线时走本地计算
联网但本地数据完整时仍优先走本地计算
远程 Web / 调试 / 服务端场景可走 API
两条路径字段一致，UI 不关心来源
```

### 兼容降级

需要支持：

```text
没有预算：返回 not_configured，客户端展示未设置预算
没有 AI 分类：返回 pending / none，客户端展示待整理
没有任务策略：按 due_at / remind_at / priority 展示普通提醒
没有混合流：降级到已有最近交易或最近任务
Local Core 不可用：repository 可降级到 API，但 UI 不写假数据
API 不可用：repository 可继续使用本地数据
```

### 多端不共享僵硬布局

```text
手机端：首页 / 备忘 / AI / 记账 / 任务，AI 为居中主按钮
Web / 桌面端：允许侧边导航、更多入口、更高信息密度
平板 / 宽屏：允许双列卡片和详情分栏
```

业务契约共享，布局形态不强行一致。

## 开发阶段

### 阶段一：本地 Home Overview read model

状态：基础本地链路已落地。

已完成：

```text
LocalCoreBridge.getHomeOverview
LocalHomeOverviewBuilder
HomeOverviewRepository 云端优先读取，失败后本地 fallback
HomePage 消费 HomeOverview repository，不再直接写死调用 /dashboard
本地 recent_activity 支持 memo / task / ledger_transaction 混合流
本地 attention_items 支持逾期任务和今天截止任务
本地 daily_trend 基于本周账单计算
本地 budget_state 返回 not_configured，不伪造预算
finance_overview 已扩展预算金额、预算使用、预算进度、预算剩余、分类占比和财务洞察字段
repository_local_mode_test 覆盖本地 Home Overview
sync_summary 已接入客户端 PowerSync currentStatus、上传错误与附件同步统计
服务端 sync_summary 已接入 PowerSync 配置状态与附件同步统计，不伪造客户端在线状态
import_summary 已接入本地与服务端最新 import_batches
settings_summary 已接入本地数据库和服务端配置完整性，且不暴露敏感配置
PowerSync schema 已补入 import_batches；infra/powersync-required-tables.txt 与 scripts/check-powersync-sync-scope.sh 用于约束各部署环境同步范围
```

仍待补齐：

```text
首页 UI 消费扩展后的 finance_overview.category_breakdown / insights 与状态摘要
任务预警策略未来几天 warning 事项继续增强 attention_items 排序
```

平台重点：Flutter Local Core / 本地 SQLite / repository / 服务端同构 API。

目标：先实现本地首页聚合 read model，再提供云端同构 API。

本地主入口建议：

```text
LocalCoreBridge.getHomeOverview(params, context)
HomeOverviewRepository.load(sourcePreference: cloudPreferred)
```

云端正常读取入口：

```text
GET /api/v1/home/overview
```

最小返回：

```text
schema_version
generated_at
user_timezone
source_mode
attention_items[]
today_metrics
finance_overview
finance_insights[]
recent_activity[]
sync_summary
import_summary
settings_summary
```

注意事项：

```text
/dashboard 保留为轻量兼容接口
首页 UI 不自己拼接紧急事项和预算状态
recent_activity 必须支持 memo / task / ledger_transaction / import_batch / capture_session
本地 Local Core 和云端 API 字段保持同构
没有网络时首页仍可展示已有本地数据
```

完成后回写：

```text
doc/api/api-contract.md
doc/architecture/sync-and-offline.md
doc/design/client-app.md
doc/design/ui-information-architecture.md
doc/guide/testing-quality.md
```

### 阶段二：Ledger budgets 与分类聚合

状态：预算写入与分类预算闭环已落地，聚合增强和 UI 消费待补。

已完成：

```text
服务端 LedgerBudget 模型与 revision
PowerSync ledger_budgets schema、CRUD 上传和云端陈旧版本判定
GET /api/v1/ledger/overview
GET /api/v1/ledger/categories/summary
GET /api/v1/ledger/insights
GET / POST / PUT / DELETE /api/v1/ledger/budgets
LocalCoreBridge ledger overview / category summary / insights
LocalCoreBridge budget list / create / update / delete
LedgerRepository 预算读取云端优先，失败后本地 fallback
总预算和支出分类预算
active 预算唯一性、分类校验、金额与阈值校验
预算软删除、恢复和 ledger_budget 审计快照
Local Core 与 PowerSync 开发期 user_id 统一为 local-dev
category_id 在本地账单记录中保留
本地 ledger overview/category summary/summary 已按月份 period 过滤
没有预算时返回 not_configured，不伪造默认预算
```

仍待补齐：

```text
月环比
更细消费洞察
首页与记账页 UI 消费预算进度、分类占比和洞察
```

平台重点：本地数据模型 / PowerSync schema / Local Core query service / repository / 服务端同构 API。

目标：预算、分类占比、月环比和消费洞察云端可拉取，同步后本地可计算，并在云端失败时本地兜底。

能力：

```text
ledger_budgets
local ledger overview
local category summary
local ledger insights
budget_state: configured / not_configured
```

本地主入口建议：

```text
LocalCoreBridge.getLedgerOverview(period)
LocalCoreBridge.getLedgerCategorySummary(period, direction)
LocalCoreBridge.getLedgerInsights(period)
LocalCoreBridge.listLedgerBudgets(period)
LocalCoreBridge.createLedgerBudget(input)
LocalCoreBridge.updateLedgerBudget(input)
LocalCoreBridge.deleteLedgerBudget(input)
```

云端正常读取入口：

```text
GET /api/v1/ledger/overview?period=YYYY-MM
GET /api/v1/ledger/categories/summary?period=YYYY-MM&direction=expense
GET /api/v1/ledger/insights?period=YYYY-MM
GET / POST / PUT / DELETE /api/v1/ledger/budgets
```

完成后回写：

```text
doc/architecture/data-model.md
doc/architecture/sync-and-offline.md
doc/api/api-contract.md
doc/requirements/ledger-system.md
doc/guide/testing-quality.md
```

### 阶段三：Memo AI 分类与标签元数据

状态：功能地基已落地，UI 消费待补。

已完成：

```text
服务端 MemoClassification / TagMetadata 模型
PowerSync memo_classifications / tag_metadata schema
服务端与本地 Memo 分类生成器
备忘创建 / 更新自动生成 AI 分类建议
备忘分类读取、生成、确认、拒绝接口
标签统计接口
tag_metadata 列表 / 创建更新 / 删除接口
LocalCoreBridge memo classifications / tag summary / tag metadata
MemoRepository 分类读取、生成、确认、拒绝、标签统计、标签元数据管理
rejected 分类不进入标签统计
Memo.tags 保留兼容但不代表 AI 分类状态
```

仍待补齐：

```text
备忘页 UI 消费分类状态、标签颜色和筛选
更复杂的语义分类模型或可插拔本地模型
```

平台重点：本地数据模型 / PowerSync schema / Local Core query service / Flutter repository / 服务端同构 API。

目标：`Memo.tags` 不再承担完整分类系统，AI 分类状态和标签元数据必须本地可查、可筛选、可统计。

能力：

```text
memo_classifications
tag_metadata
classification_source: ai / user / rule / import
classification_status: pending / suggested / confirmed / rejected
classification_confidence
local tag summary
```

本地主入口建议：

```text
LocalCoreBridge.searchMemos(filters)
LocalCoreBridge.getMemoClassifications(memoId)
LocalCoreBridge.generateMemoClassifications(memoId)
LocalCoreBridge.getTagSummary(kind)
LocalCoreBridge.listTagMetadata(kind)
LocalCoreBridge.upsertTagMetadata(input)
LocalCoreBridge.deleteTagMetadata(name)
```

云端正常读取入口：

```text
GET /api/v1/memos?tag=&classification_status=&type=&limit=&cursor=
GET /api/v1/memos/{memo_id}/classifications
POST /api/v1/memos/{memo_id}/classifications/generate
POST /api/v1/memos/{memo_id}/classifications/confirm
POST /api/v1/memos/{memo_id}/classifications/reject
GET /api/v1/tags/summary?kind=memo
GET /api/v1/tags/metadata?kind=memo
POST /api/v1/tags/metadata
DELETE /api/v1/tags/metadata/{tag_name}?kind=memo
```

完成后回写：

```text
doc/architecture/data-model.md
doc/architecture/sync-and-offline.md
doc/api/api-contract.md
doc/requirements/memo-doc-system.md
doc/design/ui-information-architecture.md
```

### 阶段四：Task reminder strategies

状态：基础链路已落地。

已完成：

```text
服务端 TaskReminderStrategy / Reminder 模型
PowerSync task_reminder_strategies / reminders schema
服务端与本地任务预警策略生成器
任务创建 / 更新自动生成提醒策略建议
GET /api/v1/tasks?group=today|urgent|warning|all
GET /api/v1/tasks/reminders
GET /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/generate
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
LocalCoreBridge task reminder strategy 生成、读取、确认、dismiss、reminders 读取
TaskRepository generateReminderStrategy / reminders / reminderStrategy / confirmReminderStrategy / dismissReminderStrategy
没有策略时返回 null，不伪造 AI 预警
策略确认后才写入 Task.remind_at
策略确认后写入 pending reminders
dismissed 策略不参与任务分组
```

仍待补齐：

```text
任务页 UI 消费策略状态和 reminders 队列
首页 attention_items 继续增强未来几天准备事项排序
系统通知 / App 内提醒派发
```

平台重点：本地数据模型 / PowerSync schema / Local Core strategy service / reminder 边界 / Flutter repository / 服务端同构 API。

目标：普通提醒字段和 AI 预警策略分离，并且预警列表、紧急分组和提前准备建议本地可计算。

能力：

```text
task_reminder_strategies
warning_level: critical / warning / normal
warning_reason
preparation_window_days
ai_suggested_remind_at
strategy_status: suggested / confirmed / dismissed / expired
local task warning groups
```

本地主入口建议：

```text
LocalCoreBridge.listTasks(group)
LocalCoreBridge.generateTaskReminderStrategy(taskId)
LocalCoreBridge.getTaskReminderStrategy(taskId)
LocalCoreBridge.confirmTaskReminderStrategy(taskId)
LocalCoreBridge.dismissTaskReminderStrategy(taskId)
LocalCoreBridge.listTaskReminders(status)
```

云端正常读取入口：

```text
GET /api/v1/tasks?group=today|urgent|warning|all
GET /api/v1/tasks/reminders
GET /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/generate
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
```

完成后回写：

```text
doc/architecture/data-model.md
doc/architecture/sync-and-offline.md
doc/api/api-contract.md
doc/requirements/task-reminder-system.md
doc/guide/testing-quality.md
```

### 阶段五：手机端 5 底部导航 Shell

状态：基础 Shell 已落地。

平台重点：Flutter 手机端 UI / Web 与桌面端适配。

目标：手机端主导航固定为：

```text
首页 / 备忘 / AI / 记账 / 任务
```

规则：

```text
AI 是居中主按钮
搜索降级为首页顶部全局搜索和页面内搜索
设置降级为首页入口和数据状态卡片入口
Web / 桌面端可以保留侧边导航和更多管理入口
页面默认消费本地 repository 数据，不直接依赖云端聚合接口
```

已完成：

```text
AppShell 手机端底部入口已收敛为：首页 / 备忘 / AI / 记账 / 任务
AI 位于中间并以主按钮形态强化
搜索和设置不再占用手机端底部一级入口
首页 AppBar 提供全局搜索和设置入口
宽屏 Flutter 形态使用同一组核心入口的 NavigationRail，避免手机底栏硬套到桌面/网页
widget test 覆盖 5 入口、AI 页切换、搜索/设置退出底部导航
```

仍待补齐：

```text
首页数据状态摘要卡片跳转设置/同步诊断入口
Web / 桌面端更完整的搜索、设置、导入导出、诊断侧边管理入口
```

完成后回写：

```text
doc/design/client-app.md
doc/design/ui-information-architecture.md
doc/guide/current-status.md
```

### 阶段六：聊天式 AI Capture

状态：基础数据链路已落地。

平台重点：Flutter AI 页面 / Local Capture Session / 附件输入边界 / 云端 AI 解析可选兜底。

目标：把当前工程化 AI Capture 调试页升级为聊天式捕获体验。

能力：

```text
CaptureSession
CaptureTurn
候选动作确认卡片
附件 asset_ids 参与解析
语音输入占位或 STT 接入边界
本地保存 capture turns
```

已完成：

```text
服务端 McpCaptureSession 增强 session_status / committed_at / dismissed_at
服务端新增 McpCaptureTurn，parse / commit / undo 会写入 turn 记录
PowerSync schema 新增 mcp_capture_sessions / mcp_capture_turns
PowerSyncCaptureStore 新增本地 captureParse / captureCommit / captureUndo
PowerSyncLocalCoreBridge.captureParse / captureCommit / captureUndo 已接入本地持久化
AiCaptureService 本地模式可走 Local Core，不再只能依赖 Cloud MCP
本地 commit 创建的 memo / task / ledger_transaction 会写入 source_capture_id
本地 undo 通过 mcp_undo_actions 转为 ai_trashed，并写入 undo turn
本地 capture_parse 已具备最小规则拆分，可从一句话生成 task_create / expense_create / memo_create 候选动作
```

当前本地主入口：

```text
LocalCoreBridge.captureParse(input, context)
LocalCoreBridge.captureCommit(input, context)
LocalCoreBridge.captureUndo(input, context)
```

当前云端入口：

```text
POST /api/v1/mcp/capture/parse
POST /api/v1/mcp/capture/commit
POST /api/v1/mcp/capture/undo
```

仍待补齐：

```text
真正聊天式多轮 append turn UI 与体验
asset_ids 参与云端/本地解析规则，而不是只作为 payload 引用边界
语音输入与 STT
更完整的 capture session 列表、恢复和取消接口
本地规则解析继续补充更多自然语言金额、日期、商户和任务拆分边界
```

边界：

```text
复用现有 capture_parse / capture_commit / capture_undo 业务能力
不绕过 audit log
不绕过 undo
附件只传 asset 引用，不把附件二进制塞进文本
没有 STT 时不伪装语音识别已完成
云端 AI 可用于解析，但 capture session、确认卡片、提交结果必须能本地持久化
```

完成后回写：

```text
doc/design/ai-interaction.md
doc/api/api-contract.md
doc/design/client-app.md
doc/architecture/sync-and-offline.md
doc/guide/testing-quality.md
```

## 发布门槛

本计划完成时必须满足：

```text
Local Core tests 通过
Flutter analyze/test 通过
服务端同构 API 测试通过
新增 read model 有本地 DTO / repository 测试
手机端主要路径可离线手动验收
云端失败或断网后首页仍可展示本地概览
没有假预算
没有假分类占比
没有假消费洞察
没有假 AI 分类状态
没有假任务预警策略
没有客户端写死首页 attention 规则
```

## 完成后的文档回写与删除流程

每完成一个阶段：

```text
更新对应固定文档
更新 doc/guide/current-status.md
更新 doc/guide/pending-tasks.md
更新 doc/guide/testing-quality.md 中的验收项
提交代码和文档
```

全部阶段完成后：

```text
确认固定文档已经包含最终事实
删除 doc/plan/mobile-product-foundation.md
保留或更新 doc/plan/README.md 的流程说明
提交删除计划文档
```

## 当前下一步建议

下一步进入：

```text
Reminder 派发状态与平台通知适配边界
```

原因：首页状态摘要与预算完整写入闭环已经具备云端、Local Core 和 PowerSync 同构能力；当前任务策略虽然能生成并写入 pending reminders，但尚未形成 pending / delivered / failed / cancelled 状态流转，也没有与 Android、桌面端和 Web 通知实现解耦的派发适配边界。先补齐平台无关的 Reminder dispatcher 与状态机，才能在后续 UI 阶段安全接入各端通知。
