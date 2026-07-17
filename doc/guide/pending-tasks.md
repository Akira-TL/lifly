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
v0.7 Product Foundation
v0.8 Cross-platform Theme Application Framework
v0.8.1 Web Minimal Shell & Global Navigation
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
首页、预算、分类、任务预警与聊天式 AI Capture 数据地基
跨端 Theme Runtime、主题包缓存、受控布局和 Web Core-first 启动
Web 极简 Shell、全局管理中心、共享页面状态和导航持久化
```

## 2. 当前任务池：Web UI/UX 与产品消费层

### LC-0800 Cross-platform theme application framework

状态：已完成。

目标：建立可扩展、可授权、可商业化预留的跨端主题框架，同时保证默认 Lifly Core 极致轻量。

验收：

```text
Lifly Core 内置、不可卸载、无远程资源和自定义字体依赖
Theme Manifest / Semantic Tokens / Platform Overrides 严格校验
主题选择和色彩模式设备本地持久化
Web / phone / desktop 使用共享 Runtime 和受控布局
坏更新保留上一 active 版本，损坏版本可以回滚
授权失败按声明 fallback，最终回到 Core
Web HTML 启动壳和 Flutter Core 首帧不等待主题缓存
默认 Web 与 Wasm Release 构建通过性能门禁
```

后续主题商业能力：正式主题目录、生产签名公钥、付费授权 API、订阅与恢复购买、主题推荐、第三方投稿和审核。这些能力必须复用现有 Theme Package 与 Entitlement 边界，不能把远程主题升级为任意代码插件。

### LC-0810 Web minimal shell and global navigation

状态：已完成。

目标：为后续 Web 首页、备忘、记账、任务和 AI 页面改造提供稳定宽屏外壳。

验收：

```text
Web dashboard 使用 248px 可折叠侧栏，桌面 compact 和手机五入口保持独立布局
首页、备忘、AI、记账、任务五个核心入口不被低频管理能力挤占
搜索、快速记录和管理中心可达
管理中心组织账单导入、导入批次、数据导出、附件库、设置与诊断
侧栏折叠和当前核心入口跨 AppShell 重建恢复
管理页返回和主题切换保持当前核心页与 API 实例
Ctrl+K / Ctrl+N 在输入框聚焦时让路
Loading / Empty / Error / Offline 使用共享页面状态
默认 Web 与 Wasm Release 构建通过 v0.8.1 发布门禁
```

### Web UI/UX 后续切片

```text
Web 极简 Shell 与全局导航（已完成）
Web 首页真实 Home Overview 消费（下一阶段）
Web 备忘 AI 分类和标签消费
Web 记账预算、分类占比和洞察消费
Web 任务预警策略和提醒状态消费
Web AI、附件、导入导出、搜索、设置和诊断
多端响应式、键鼠、可访问性和发布门禁
```

### 既有 v0.7 产品地基后续

### LC-0701 Local Home Overview read model

状态：云端 /api/v1/home/overview 与本地 fallback 基础链路已完成，预算进度、分类占比、财务洞察和真实状态摘要已扩展；首页 UI 消费扩展字段与未来任务预警排序待补。

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
sync_summary 读取 PowerSync currentStatus 或服务端真实同步配置与附件统计
import_summary 读取最新 import_batches，不固定返回 idle
settings_summary 只返回本地数据库与服务端配置完整性，不泄露敏感配置
云端失败或断网时首页仍可展示已有本地概览
```

### LC-0702 Ledger budgets and category aggregation

状态：预算完整写入闭环与分类预算已完成；月环比、更细消费洞察和页面消费待补。

目标：补齐预算、分类占比、月环比和消费洞察地基。

验收：

```text
ledger_budgets 模型明确，并带 revision
PowerSync ledger_budgets schema、CRUD 上传和云端陈旧版本判定已接入
服务端与 Local Core 支持总预算、支出分类预算的列表、创建、更新、软删除和恢复
同一用户、月份和分类范围只允许一个 active 预算
预算写入记录 ledger_budget 审计快照
Local Core ledger overview/category summary/insights 可本地计算
云端 ledger overview/category summary/insights 接口已提供正常读取入口
LedgerRepository 预算读取支持云端优先、失败后本地 fallback
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

状态：策略与 Reminder 派发状态机已完成，平台适配边界已建立；具体 Android/桌面/Web 通知插件接入和任务页 UI 消费待补。

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
Reminder 支持 pending / delivered / failed / cancelled 状态
到期提醒通过 dispatch token + lease 幂等认领
失败按 next_attempt_at 指数退避并支持手动 retry
任务完成、取消、删除或策略 dismiss 会取消未送达提醒
Reminder 状态通过 PowerSync revision 同步并拒绝陈旧写入
平台通知通过 ReminderNotificationAdapter 接入，不绑定单一插件
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

状态：连续会话、聊天式多轮 UI、附件上下文与撤销/修改链路已完成；PDF 文本提取、图片 OCR/视觉、音频 STT 和外部链接内容抓取适配器待补。

目标：保证 AI 聊天可以恢复历史、持续追加 turn，并让每一轮 AI 已设置内容可查看、修改、提交和撤销。

验收：

```text
服务端与 Local Core 支持 session 列表、读取、恢复、append turn 和 dismiss
McpCaptureTurn 持久化 user / assistant / system 角色、asset_ids、asset_context、actions、result_entities、undo_token 和 supersedes_turn_id
commit 只作用于具体 assistant turn，session 提交后仍可继续对话
未执行候选动作可 revise；已执行 turn 必须先 undo，之后可修改并重新提交
PowerSync 同步 capture_session / capture_turn revision，PATCH 不清空 text / actions / asset_ids / asset_context / result_entities 等历史字段
本地 commit 创建实体时写入 source_capture_id
本地 undo 使用 mcp_undo_actions 并将实体转为 ai_trashed
AiCaptureService 提供强类型 assets/list/get/append/revise/commit/undo/dismiss 接口
Flutter AI 页面消费历史 turns、宽屏会话侧栏、手机历史面板、结果实体卡片、修改、撤销、附件选择和会话关闭
服务端可安全提取受限 UTF-8 文本附件；PDF/图片/音频/外链明确返回待接入能力，不伪造解析完成
回归测试覆盖连续第二轮、修改、提交、撤销、撤销后再次修改、关闭会话、附件上下文与结果卡片
本地 capture_parse 最小规则拆分覆盖 task_create / expense_create / memo_create 候选动作
```

### LC-0707 Product foundation release gate

状态：已完成。

目标：确认 v0.7 产品地基没有假数据和客户端硬编码产品规则。

验收：

```text
服务端、Flutter 与 PowerSync 完整检查通过
首页和记账 repository 覆盖云端失败后的 Local Core fallback
AI Capture 连续会话、修改、提交和撤销可在 Local Core 独立运行
附件库使用真实文件选择、对象存储 PUT 和 upload-complete，不保留占位文件名
Fake Local Core 按备忘、记账、任务和 Capture store 拆分
PowerSync Capture / Task 的规则、编解码与 SQL 辅助已拆分
Dart / Python 业务文件通过 800 行体积门禁
scripts/check-v0.7-release-gate.sh 固化发布检查
已完成计划回写并删除 mobile-product-foundation 计划文档
```

后续增强能力：PDF 正文提取、图片 OCR/视觉、音频 STT、外部链接正文抓取、具体平台系统通知插件与正式数据库 migration runner。这些能力不阻塞 v0.7.0 产品地基发布。
