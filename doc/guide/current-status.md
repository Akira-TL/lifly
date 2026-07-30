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

状态：已完成地基阶段，页面消费继续迭代。

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
Home Overview 基础链路已落地：服务端 /api/v1/home/overview、LocalCoreBridge.getHomeOverview、LocalHomeOverviewBuilder、HomeOverviewRepository 云端优先/失败 fallback、HomePage repository 消费、云端/本地混合最近活动流；finance_overview 已扩展预算金额、预算使用、预算进度、预算剩余、分类占比和财务洞察字段；sync_summary 已接入客户端 PowerSync currentStatus 与服务端附件同步统计，import_summary 已接入最新 import_batches，settings_summary 已接入本地数据库与服务端配置完整性
Ledger budgets 与分类聚合写入闭环已落地：服务端与 Local Core 支持总预算和支出分类预算的列表、创建、更新、软删除、恢复与审计；PowerSync ledger_budgets 已接入 revision、CRUD 上传和服务端陈旧版本判定；LedgerRepository 预算读取云端优先/失败后本地 fallback，离线写入走 Local Core；/ledger/overview、/ledger/categories/summary、/ledger/insights 与本地月份聚合继续保持同构
Memo AI 分类与标签元数据基础链路已落地：MemoClassification、TagMetadata、PowerSync memo_classifications/tag_metadata schema、备忘分类生成/确认/拒绝接口、/tags/summary、/tags/metadata 管理接口、服务端与本地创建/更新自动生成分类建议、MemoRepository 分类生成/标签统计/标签元数据管理
Task reminder strategies 与派发状态机已落地：TaskReminderStrategy、Reminder、PowerSync task_reminder_strategies/reminders schema、任务分组 group、策略生成/读取/确认/dismiss；Reminder 支持 pending/delivered/failed/cancelled、到期认领 lease、dispatch token、指数退避、手动 retry、取消与审计，TaskRepository 和 Local Core 提供同构状态操作；ReminderDispatcher 通过平台无关 ReminderNotificationAdapter 投递，reminder ID 作为稳定幂等键，尚未绑定具体 Android/桌面/Web 通知插件
手机端 5 底部导航 Shell 基础链路已落地：AppShell 收敛为首页 / 备忘 / AI / 记账 / 任务，AI 为居中主按钮，搜索/设置降级到首页入口，宽屏 Flutter 使用 NavigationRail
Local Chat-style AI Capture 连续会话与消费层已落地：服务端与 Local Core 支持 session 列表、读取、恢复、append turn、候选动作 revise、逐 turn commit、undo 和 dismiss；用户 turn、AI 候选动作、result_entities、undo_token、asset_ids、asset_context 与 supersedes 版本链持久化到 PowerSync，commit 不再关闭整个会话，已执行内容必须先 undo 才能修改并重新提交；服务端可安全提取受限 UTF-8 文本附件，PDF/图片/音频/外链明确返回待接入能力；Flutter AI 页面已消费历史 turns、会话列表、候选卡片、已设置结果、修改、撤销、附件选择和关闭会话，宽屏与手机使用不同会话导航形态
v0.7.0 产品地基发布门禁已收口：Fake Local Core 按备忘、记账、任务、Capture 拆分，PowerSync Capture 与 Task Store 的规则/SQL 辅助已拆分，Dart/Python 业务文件统一纳入 800 行门禁；附件库已移除硬编码占位上传，改为真实文件选择、对象存储上传和 upload-complete；scripts/check-v0.7-release-gate.sh 统一检查服务端、Flutter、PowerSync、离线 fallback、假数据残留、源码体积与计划清理
```

验收：

```text
首页、预算、分类、洞察、AI 分类、任务预警正常优先来自云端拉取和同步，云端失败或断网时来自 Local Core / PowerSync 本地 read model
云端 API 与本地 read model 字段同构，云端负责正常拉取和同步，本地负责失败兜底和离线可用
客户端不写假数据、不硬编码长期产品规则
手机端、Web、桌面端共享业务语义但可以使用不同布局
```

## M7：Cross-platform Theme Application Framework

状态：已完成。

目标：建立 Web、手机端和桌面端共享的多主题应用框架，保证默认 Core 极致轻量，并为未来主题商店、付费授权和推荐机制预留稳定边界。

范围：

```text
Lifly Core 内置兜底主题
声明式 Theme Manifest / Semantic Tokens
Theme Runtime 与设备偏好
system / light / dark / OLED / highContrast 协议
Web / phone / desktop 平台 Profile
compact / balanced / dashboard 受控布局
主题包版本缓存、摘要、资源、签名和授权占位
已知可用版本回滚与 fallback 链
Web HTML 启动壳与 Core-first 首帧
默认 Web / Wasm Release 双构建门禁
```

当前进展：

```text
Theme Runtime 启动时同步提供 Lifly Core，设备偏好、缓存主题、授权和可选资源只在 Core 首帧后恢复
Manifest 严格校验主题身份、版本、平台、色彩模式、性能等级、资源、fallback、授权类型、平台覆盖和完整性元数据；远程主题不能执行 Dart、脚本、API 或查询
Lifly Core 使用系统字体和内置语义 Token，不依赖远程资源、自定义字体、大型装饰资源或持续动画
主题选择与色彩模式已进入设置页，切换主题不重建 API、PowerSync、Local Core、AI 服务和当前路由
手机端最小交互区域 48px，Web dashboard 可展开侧栏，桌面 compact 使用紧凑侧栏；Hover、Focus、键盘遍历和系统减少动态效果已接入
原生端使用文件版本槽位和可恢复 active 指针，Web 使用版本化键值缓存；坏更新保留旧版本，损坏 active 可以回滚
主题授权通过独立 Entitlement Provider 判断，离线授权可用，失败按声明 fallback 并最终回到 Lifly Core
Web 宿主记录 host feedback、entrypoint、engine、Dart entrypoint、first frame、Core usable 和 theme activated 里程碑
默认 Web 与 Wasm Release 构建均通过；当前 main.dart.js 为 3,526,419 bytes，main.dart.wasm 为 3,187,224 bytes
scripts/check-web-theme-performance.sh 与 CI 固化启动契约、主题安全、产物预算和双构建检查
```

验收：

```text
任意主题失败不阻塞 Lifly Core
新增主题不要求业务页面新增主题分支
远程主题是声明式内容，不是插件
默认主题启动不等待网络、同步、授权或主题缓存
主题功能在 Web、手机端和桌面端保持一致，平台只调整受控表现
```

## M8：Web Minimal Shell & Global Navigation

状态：已完成。

目标：把跨端主题和布局地基落成可承载后续 Web 页面改造的稳定产品外壳，同时保持手机端五入口和桌面 compact 行为。

范围：

```text
Web dashboard 218px 自定义侧栏，折叠后 64px
首页 / 备忘 / AI / 记账 / 任务五核心入口
全局搜索与 AI 快速记录
账单导入 / 导入批次 / 数据导出 / 附件 / 设置诊断管理中心
侧栏折叠与当前核心入口设备本地持久化
Ctrl+K / Ctrl+N 全局快捷键与输入焦点保护
Loading / Empty / Error / Offline 共享页面状态
默认 Web / Wasm Release 构建和 Shell 发布门禁
```

当前进展：

```text
Web dashboard 侧栏展示 Lifly 品牌、生活数据中心说明、高频动作和五个核心入口；桌面 compact 保持紧凑侧栏，手机端继续使用五入口底栏和 48px 触控边界
附件、账单导入、导入批次、数据导出、设置与诊断收敛到单一管理中心；管理中心只组织路由，不复制 Repository、API、Local Core 或 PowerSync 状态
侧栏折叠和当前核心入口通过 ShellPreferenceStore 保存；AppShell 重建后恢复，非法索引被忽略
管理中心返回和 Web 主题切换保持当前核心页面与 API 服务实例
Ctrl+K 打开搜索、Ctrl+N 进入 AI 快速记录；EditableText 聚焦时全局 Action 自动禁用
AsyncContentScaffold 已统一 Loading、Empty、Error、Offline 状态；附件库完成首批真实消费，备忘、记账和任务保持兼容
Flutter analyze 与 143 项客户端测试通过，v0.8.1 发布门禁同时覆盖默认 Web 和 Wasm 构建
```

验收：

```text
全局导航和业务内容边界清楚
低频管理能力可达但不挤占五核心入口
浏览器刷新、管理页返回和主题切换保持 Shell 状态
文本编辑不被全局快捷键打断
Web、桌面 compact 和手机端无导航回归
```

## M9：Web Home Attention Workbench

状态：已按原型重构并通过自动检查，待浏览器视觉验收。

目标：把已确认的 A 方向“今日处理队列”按结构而不是仅按信息层级落到真实 Web 首页。

范围：

```text
Lifly Core 使用原型的绿色与中性灰语义色
Web 默认 dashboard 使用 218px 自定义侧栏，折叠后 64px
首页使用 68px 左对齐“今天”顶栏
主工作区展示处理队列、本月收支和最近备忘
右侧日程栏展示日期、真实时间事项和同步状态
手机端保留既有 HomeDashboardView
```

当前进展：

```text
Web 不再使用 Material NavigationRail 作为展开侧栏；桌面 compact 仍保留紧凑 NavigationRail
首页移除了上一版额外增加的来源状态面板、五项指标条、七日柱状图和混合活动面板
attention_items 最多四条进入处理队列；finance_overview 生成支出、预算余量和主要分类比例行；recent_activity 只提取最近备忘
带 occurred_at 的 attention_items 进入右侧时间线，sync_summary 在底部显示真实数据状态
主题包语义色继续通过 LiflySemanticColors 注入 ThemeData，业务页面不解析主题包或写死状态色
最大源码文件为 wide_shell.dart 674 行，首页主视图为 533 行，符合 800 行门禁
Flutter analyze 与 146 项测试通过；默认 Web main.dart.js 为 3,609,549 bytes，应用 main.dart.wasm 为 3,271,607 bytes，均通过既有预算
```

验收：

```text
1440px Web 展示 218px 侧栏、主工作区和独立日程右栏
较窄 Web 将日程移动到主内容下方，不把手机布局直接放大
首页真实字段可见且云端失败后仍由既有 Local Core fallback 提供
Web 首页不创建 Material Card 堆叠，不显示装饰性渐变或额外 Dashboard 模块
桌面 compact 与手机端导航无回归
```

## M10：Desktop Local MCP & Production Hardening

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
