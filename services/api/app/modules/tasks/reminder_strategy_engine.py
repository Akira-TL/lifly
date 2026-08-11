from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Reminder, Task, TaskReminderStrategy
from app.modules.tasks.time_reasoning import build_task_time_facts


@dataclass(frozen=True)
class TaskReminderSuggestion:
    warning_level: str
    warning_reason: str
    preparation_window_days: int | None
    ai_suggested_remind_at: datetime | None


PREPARATION_KEYWORDS: tuple[tuple[str, int, str], ...] = (
    ("考试", 7, "考试类任务通常需要提前一周准备。"),
    ("签证", 7, "签证/证件类事项周期较长，建议提前准备。"),
    ("旅行", 3, "出行类任务需要提前整理行程和物品。"),
    ("露营", 3, "露营需要提前检查装备和采购。"),
    ("出行", 3, "出行类任务需要提前准备。"),
    ("项目", 2, "项目类任务通常需要提前拆解和推进。"),
    ("周报", 1, "报告类任务建议提前一天整理材料。"),
    ("报告", 1, "报告类任务建议提前一天整理材料。"),
    ("提交", 1, "提交类任务建议提前一天检查。"),
    ("房租", 0, "支付类任务临近截止时需要明确提醒。"),
)


def suggest_task_reminder_strategy(task: Task, *, now: datetime | None = None) -> TaskReminderSuggestion | None:
    facts = build_task_time_facts(task, now=now or datetime.now(timezone.utc))
    baseline = facts.now_utc
    due_at = facts.due_at_utc
    title_text = f"{task.title or ''}\n{task.description or ''}"
    keyword_window = _preparation_window(title_text)

    if due_at is None and keyword_window is None:
        return None

    if due_at is None:
        days, reason = keyword_window or (None, "任务需要进一步确认提醒时间。")
        return TaskReminderSuggestion(
            warning_level="normal",
            warning_reason=reason,
            preparation_window_days=days,
            ai_suggested_remind_at=None,
        )

    if facts.is_overdue:
        return TaskReminderSuggestion(
            warning_level="critical",
            warning_reason="任务已过截止时间，需要立即处理。",
            preparation_window_days=0,
            ai_suggested_remind_at=baseline,
        )

    remaining = timedelta(seconds=facts.remaining_seconds or 0)
    if task.priority == "urgent" or remaining <= timedelta(hours=6):
        return TaskReminderSuggestion(
            warning_level="critical",
            warning_reason="任务距离截止时间很近，需要立即关注。",
            preparation_window_days=0,
            ai_suggested_remind_at=max(baseline, due_at - timedelta(hours=2)),
        )

    days, reason = keyword_window or _default_window(remaining, task.priority)
    remind_at = _suggested_remind_at(due_at, baseline, days)
    warning_level = _warning_level(
        due_at=due_at,
        now=baseline,
        preparation_window_days=days,
        priority=task.priority,
    )
    return TaskReminderSuggestion(
        warning_level=warning_level,
        warning_reason=reason,
        preparation_window_days=days,
        ai_suggested_remind_at=remind_at,
    )


async def ensure_task_reminder_strategy(
    db: AsyncSession,
    task: Task,
    *,
    replace_suggested: bool = True,
) -> TaskReminderStrategy | None:
    suggestion = suggest_task_reminder_strategy(task)
    if suggestion is None:
        return None

    existing = await _active_strategy(db, task)
    if existing and existing.strategy_status == "confirmed":
        return existing
    if existing and existing.source == "ai" and replace_suggested:
        strategy = existing
    else:
        strategy = TaskReminderStrategy(user_id=task.user_id, task_id=task.id, source="ai")
        db.add(strategy)

    strategy.warning_level = suggestion.warning_level
    strategy.warning_reason = suggestion.warning_reason
    strategy.preparation_window_days = suggestion.preparation_window_days
    strategy.ai_suggested_remind_at = suggestion.ai_suggested_remind_at
    strategy.strategy_status = "suggested"
    strategy.source = "ai"
    await db.flush()
    return strategy


async def ensure_reminder_for_strategy(
    db: AsyncSession,
    *,
    task: Task,
    strategy: TaskReminderStrategy,
) -> Reminder | None:
    remind_at = strategy.ai_suggested_remind_at or task.remind_at
    if remind_at is None:
        return None
    result = await db.execute(
        select(Reminder)
        .where(
            Reminder.user_id == task.user_id,
            Reminder.target_type == "task",
            Reminder.target_id == task.id,
            Reminder.channel == "app",
            Reminder.reminder_status.in_(["pending", "failed"]),
        )
        .order_by(Reminder.created_at.desc())
        .limit(1)
    )
    reminder = result.scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if reminder is None:
        reminder = Reminder(
            user_id=task.user_id,
            target_type="task",
            target_id=task.id,
            remind_at=remind_at,
            channel="app",
            reminder_status="pending",
            next_attempt_at=remind_at,
        )
        db.add(reminder)
    else:
        reminder.remind_at = remind_at
        reminder.reminder_status = "pending"
        reminder.attempt_count = 0
        reminder.next_attempt_at = remind_at
        reminder.failed_at = None
        reminder.last_error = None
        reminder.dispatch_token = None
        reminder.lease_until = None
        reminder.updated_at = now
        reminder.revision += 1
    await db.flush()
    return reminder


async def _active_strategy(db: AsyncSession, task: Task) -> TaskReminderStrategy | None:
    result = await db.execute(
        select(TaskReminderStrategy)
        .where(
            TaskReminderStrategy.user_id == task.user_id,
            TaskReminderStrategy.task_id == task.id,
            TaskReminderStrategy.strategy_status != "dismissed",
        )
        .order_by(TaskReminderStrategy.updated_at.desc())
    )
    return result.scalar_one_or_none()


def _preparation_window(text: str) -> tuple[int, str] | None:
    for keyword, days, reason in PREPARATION_KEYWORDS:
        if keyword in text:
            return days, reason
    return None


def _default_window(remaining: timedelta, priority: str | None) -> tuple[int, str]:
    if priority == "high":
        return 1, "高优先级任务建议至少提前一天提醒。"
    if remaining >= timedelta(days=7):
        return 3, "截止时间较远，建议提前三天开始准备。"
    if remaining >= timedelta(days=2):
        return 1, "未来几天截止，建议提前一天提醒。"
    return 0, "任务即将截止，建议当天提醒。"


def _suggested_remind_at(due_at: datetime, now: datetime, days: int | None) -> datetime:
    if days is None:
        return due_at
    if days <= 0:
        candidate = due_at - timedelta(hours=2)
    else:
        candidate = due_at - timedelta(days=days)
    if candidate < now:
        return now
    return candidate


def _warning_level(
    *,
    due_at: datetime,
    now: datetime,
    preparation_window_days: int | None,
    priority: str | None,
) -> str:
    if priority == "urgent":
        return "critical"
    if due_at <= now + timedelta(hours=12):
        return "critical"
    if priority == "high":
        return "warning"
    if preparation_window_days is not None and preparation_window_days > 0:
        return "warning"
    if due_at <= now + timedelta(days=1):
        return "warning"
    return "normal"
