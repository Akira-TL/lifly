# 任务提醒系统

## 1. 定位

任务提醒系统用于记录待办和提醒，不等于完整日历系统。

MVP 目标：

- 快速创建任务；
- 设置提醒；
- 查看今天；
- 完成任务；
- AI 创建任务。

## 2. Task 与 Event 区别

Task：

- 可以没有开始时间；
- 可以只有提醒时间；
- 可以只有截止时间；
- 不一定占用时间段。

Event：

- 有开始/结束时间；
- 通常占用时间；
- 支持重复规则；
- 用于课程表和日历。

MVP 主要做 Task，底层预留 CalendarEvent。

## 3. Task 字段

```text
title
description
due_at
remind_at
priority
task_status
source_capture_id
status
```

## 4. Reminder 字段

```text
target_type
target_id
remind_at
channel
reminder_status: pending / delivered / failed / cancelled
attempt_count / max_attempts
next_attempt_at / last_attempt_at
delivered_at / failed_at / cancelled_at
last_error
external_id
dispatch_token / lease_until
revision
```

## 5. 提醒通道

MVP：

- App 内提醒；
- 系统通知，视平台能力实现；
- 任务列表提醒。

平台通知实现必须通过 `ReminderNotificationAdapter` 边界接入，业务层不直接依赖 Android、桌面端或 Web 的某个通知插件。适配器接收稳定的 reminder ID 作为幂等键，并返回平台 external ID、失败原因和建议重试间隔。

后续：

- QQ/微信机器人提醒；
- 邮件提醒；
- Webhook。

## 6. AI 创建任务

输入：

```text
明天晚上 8 点提醒我改 Lifly 登录页
```

输出：

```json
{
  "title": "改 Lifly 登录页",
  "remind_at": "2026-06-22T20:00:00+08:00"
}
```

## 7. 今日视图

今日视图展示：

- 今天提醒；
- 逾期未完成；
- 最近创建；
- 已完成。

## 8. 完成任务

任务完成必须写 audit log。

状态：

```text
todo
doing
done
cancelled
```

## 9. AI 预警策略

普通提醒字段和 AI 预警策略必须分离。

当前字段职责：

```text
Task.due_at：任务截止时间
Task.remind_at：当前生效提醒时间
Reminder：提醒派发队列/记录
```

长期策略模型职责：

```text
TaskReminderStrategy：AI/规则生成的提醒建议、预警原因、提前准备窗口和用户确认状态
```

策略字段：

```text
warning_level: critical / warning / normal
warning_reason
preparation_window_days
suggested_start_at
ai_suggested_remind_at
confidence
status: suggested / confirmed / dismissed / expired
created_by: ai / user / rule
```

策略确认后，才写入或更新 `Task.remind_at` 和 `Reminder`。

Reminder 派发状态机：

```text
pending -> delivered
pending -> failed -> pending（自动或手动重试）
pending / failed -> cancelled
```

派发前先认领到期提醒，写入 `dispatch_token`、`lease_until`、`last_attempt_at` 并增加 `attempt_count`。同一 reminder ID 在多次认领和重试中保持不变，平台适配器必须据此去重。失败默认指数退避，并在达到 `max_attempts` 后停止自动认领；用户手动 retry 可重置尝试次数。任务完成、任务取消、任务删除或策略 dismissed 时，尚未 delivered 的 Reminder 必须转为 cancelled。

任务列表 read model 可以按以下分组输出：

```text
today
urgent
warning
overdue
done
all
```

客户端不能仅根据标题、颜色或固定天数伪造“AI 建议提前准备”。

## 10. 日历预留

calendar_events 表从第一版保留，用于后续：

- 课程表；
- ICS；
- Google/Apple Calendar；
- 重复日程；
- 日历视图。

## 11. 不做功能

MVP 不做：

- 甘特图；
- 项目管理；
- 团队协作；
- 复杂重复规则 UI；
- 完整日历月视图。
