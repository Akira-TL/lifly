# 05. 领域模型

## 1. 核心领域对象

Lifily 的核心对象包括：

```text
Capture       原始输入
Memo          备忘录/日记/文档
Asset         附件/外链
Ledger        账单
Task          任务
Reminder      提醒
CalendarEvent 日历事件，MVP 预留
ImportBatch   导入批次
AuditLog       审计日志
TrashState     删除状态
```

## 2. Capture

Capture 是所有 AI/自然语言输入的原始记录。

例如用户输入：

```text
今天中午食堂 18，晚上 8 点提醒我改页面，记一下今天有点累。
```

这是一条 Capture。它会被解析为多个 Action：

- expense_create；
- task_create；
- memo_create。

Capture 必须保存原始文本和解析结果，便于追踪。

## 3. Memo

Memo 是泛化的文本记录对象，不只是普通备忘录。

类型：

```text
memo      普通备忘
journal   日记
clip      摘录/剪藏
doc       长文档
```

Memo 支持 Markdown 和附件引用。

## 4. Asset

Asset 是附件和外部资源引用。

分为：

```text
internal    内部附件，存对象存储
external    外部链接，存 URL
```

Asset 可以被多个 Memo 引用。

## 5. Ledger Transaction

账单交易记录。MVP 采用简化模型：

- 金额；
- 方向；
- 账户；
- 分类；
- 商户；
- 时间；
- 备注；
- 来源。

底层预留分录结构，未来支持转账、退款、信用卡、报销等复杂场景。

## 6. Task

Task 是待办任务，不等同于日程。任务通常有：

- 标题；
- 截止时间；
- 提醒时间；
- 状态；
- 优先级。

## 7. Reminder

Reminder 是提醒对象，可以挂在：

- Task；
- CalendarEvent；
- Memo；
- Ledger Transaction。

## 8. CalendarEvent

MVP 不做完整日历 UI，但底层预留 CalendarEvent，用于未来：

- 课程表；
- ICS 导入导出；
- Google/Apple/飞书日历同步；
- 重复事件。

## 9. ImportBatch

导入批次用于 CSV 导入。所有导入都必须先进入批次预览，再 commit。批次可回滚。

## 10. AuditLog

所有创建、修改、删除、导入、导出都必须有审计日志。

AuditLog 是系统可撤销、可追踪、可解释的基础。

## 11. TrashState

所有核心对象都要支持状态：

```text
active
archived
ai_trashed
user_trashed
purged
```

AI 删除进入 ai_trashed，用户确认后才进入 user_trashed。
