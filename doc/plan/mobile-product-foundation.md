# 手机端产品地基开发计划

## 计划状态

```text
状态：待执行
当前分支：develop/v0.7.0
平台范围：服务端 API / 数据模型 / 同步 schema / Flutter repository / 手机端 UI / Web 与桌面端适配原则
当前动作：先冻结计划，不直接写业务代码
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

这些能力不能靠 Flutter 页面临时拼接，也不能在客户端写死规则。必须先补齐服务端聚合、数据模型、repository 和同步边界。

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

当前不需要继续散写正式文档。后续应以本文档作为临时执行计划，完成后再回写固定文档并删除本文档。

## 核心原则

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

这些内容必须来自：

```text
服务端 API
本地 core read model
PowerSync 同步 schema
repository DTO / entity
```

### 聚合接口必须可演进

新增聚合接口统一携带：

```text
schema_version
generated_at
user_timezone
source_mode
```

需要支持兼容降级：

```text
没有预算：返回 not_configured，客户端展示未设置预算
没有 AI 分类：返回 pending / none，客户端展示待整理
没有任务策略：按 due_at / remind_at / priority 展示普通提醒
没有混合流：降级到已有最近交易或最近任务
```

### 多端不共享僵硬布局

```text
手机端：首页 / 备忘 / AI / 记账 / 任务，AI 为居中主按钮
Web / 桌面端：允许侧边导航、更多入口、更高信息密度
平板 / 宽屏：允许双列卡片和详情分栏
```

业务契约共享，布局形态不强行一致。

## 开发阶段

### 阶段一：Home Overview read model

平台重点：服务端 API / 数据聚合 / Flutter repository。

目标：新增产品化首页聚合接口：

```text
GET /api/v1/home/overview
```

最小返回：

```text
schema_version
generated_at
user_timezone
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
首页 UI 不再自己拼接紧急事项和预算状态
recent_activity 必须支持 memo / task / ledger_transaction / import_batch / capture_session
```

完成后回写：

```text
doc/api/api-contract.md
doc/design/ui-information-architecture.md
doc/guide/testing-quality.md
```

### 阶段二：Ledger budgets 与分类聚合

平台重点：服务端数据模型 / API / repository。

目标：补齐预算、分类占比、月环比和消费洞察地基。

能力：

```text
ledger_budgets
ledger overview
category summary
ledger insights
budget_state: configured / not_configured
```

接口方向：

```text
GET /api/v1/ledger/overview?period=YYYY-MM
GET /api/v1/ledger/categories/summary?period=YYYY-MM&direction=expense
GET /api/v1/ledger/insights?period=YYYY-MM
```

完成后回写：

```text
doc/architecture/data-model.md
doc/api/api-contract.md
doc/requirements/ledger-system.md
doc/guide/testing-quality.md
```

### 阶段三：Memo AI 分类与标签元数据

平台重点：服务端数据模型 / API / 同步 schema / Flutter repository。

目标：把 `Memo.tags` 从轻量字符串列表升级为可支撑 AI 分类状态的结构化能力。

能力：

```text
memo_classifications
tag_metadata
classification_source: ai / user / rule / import
classification_status: pending / suggested / confirmed / rejected
classification_confidence
```

接口方向：

```text
GET /api/v1/memos?tag=&classification_status=&type=&limit=&cursor=
GET /api/v1/memos/{memo_id}/classifications
POST /api/v1/memos/{memo_id}/classifications/confirm
POST /api/v1/memos/{memo_id}/classifications/reject
GET /api/v1/tags/summary?kind=memo
```

完成后回写：

```text
doc/architecture/data-model.md
doc/api/api-contract.md
doc/requirements/memo-doc-system.md
doc/design/ui-information-architecture.md
```

### 阶段四：Task reminder strategies

平台重点：服务端数据模型 / API / reminder 边界 / Flutter repository。

目标：把普通提醒字段和 AI 预警策略分离。

能力：

```text
task_reminder_strategies
warning_level: critical / warning / normal
warning_reason
preparation_window_days
ai_suggested_remind_at
strategy_status: suggested / confirmed / dismissed / expired
```

接口方向：

```text
GET /api/v1/tasks?group=today|urgent|warning|all
GET /api/v1/tasks/{task_id}/reminder-strategy
POST /api/v1/tasks/{task_id}/reminder-strategy/confirm
POST /api/v1/tasks/{task_id}/reminder-strategy/dismiss
```

完成后回写：

```text
doc/architecture/data-model.md
doc/api/api-contract.md
doc/requirements/task-reminder-system.md
doc/guide/testing-quality.md
```

### 阶段五：手机端 5 底部导航 Shell

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
```

完成后回写：

```text
doc/design/client-app.md
doc/design/ui-information-architecture.md
doc/guide/current-status.md
```

### 阶段六：聊天式 AI Capture

平台重点：服务端 capture session / Flutter AI 页面 / 附件输入边界。

目标：把当前工程化 AI Capture 调试页升级为聊天式捕获体验。

能力：

```text
CaptureSession
CaptureTurn
候选动作确认卡片
附件 asset_ids 参与解析
语音输入占位或 STT 接入边界
```

接口方向：

```text
POST /api/v1/capture/sessions
POST /api/v1/capture/sessions/{session_id}/turns
POST /api/v1/capture/sessions/{session_id}/commit
POST /api/v1/capture/sessions/{session_id}/undo
```

边界：

```text
复用现有 capture_parse / capture_commit / capture_undo 业务能力
不绕过 audit log
不绕过 undo
附件只传 asset 引用，不把附件二进制塞进文本
没有 STT 时不伪装语音识别已完成
```

完成后回写：

```text
doc/design/ai-interaction.md
doc/api/api-contract.md
doc/design/client-app.md
doc/guide/testing-quality.md
```

## 发布门槛

本计划完成时必须满足：

```text
服务端测试通过
Flutter analyze/test 通过
新增 API 有 schema / DTO / repository 测试
手机端主要路径可手动验收
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
Home Overview read model
```

原因：首页是手机端第一入口，也是最容易诱发客户端临时拼接和假数据的地方。先补 `/api/v1/home/overview`，后面的备忘、记账、任务、AI Capture UI 才能消费真实接口。
