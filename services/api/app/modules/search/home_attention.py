from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.db.models import Task, TaskReminderStrategy


def build_attention_items(
    tasks: list[Task],
    strategies: dict[str, TaskReminderStrategy],
    now: datetime,
) -> list[dict[str, object | None]]:
    active_tasks = [task for task in tasks if task.task_status in {"todo", "doing"}]
    ranked: list[
        tuple[
            int,
            int,
            datetime,
            Task,
            TaskReminderStrategy | None,
            str,
            timedelta,
            timedelta,
        ]
    ] = []
    far_future = now + timedelta(days=36500)
    for task in active_tasks:
        strategy = strategies.get(task.id)
        urgency_window = _task_urgency_window(task, strategy, now)
        super_window = _task_super_urgency_window(task, strategy, urgency_window)
        quadrant = _task_quadrant(task, urgency_window, now)
        due_at = _to_utc(task.due_at) or _to_utc(
            strategy.ai_suggested_remind_at if strategy else None
        )
        stage_rank = _urgency_stage_rank(due_at, now, urgency_window, super_window)
        ranked.append(
            (
                _quadrant_rank(quadrant),
                stage_rank,
                due_at or far_future,
                task,
                strategy,
                quadrant,
                urgency_window,
                super_window,
            )
        )

    ranked.sort(key=lambda item: (item[0], item[1], item[2]))
    items: list[dict[str, object | None]] = []
    for (
        _,
        _,
        _,
        task,
        strategy,
        quadrant,
        urgency_window,
        super_window,
    ) in ranked[:8]:
        actual_due_at = _to_utc(task.due_at) or _to_utc(
            strategy.ai_suggested_remind_at if strategy else None
        )
        is_overdue = actual_due_at is not None and actual_due_at < now
        is_due_today = _same_utc_day(actual_due_at, now)
        if is_overdue:
            item_type = "task_overdue"
        elif strategy is not None:
            item_type = "task_warning_strategy"
        elif is_due_today:
            item_type = "task_due_today"
        else:
            item_type = "task_focus"
        items.append(
            {
                "id": f"focus_task_{task.id}",
                "type": item_type,
                "level": _quadrant_level(quadrant),
                "quadrant": quadrant,
                "urgency_window_seconds": max(0, int(urgency_window.total_seconds())),
                "super_urgency_window_seconds": max(
                    0, int(super_window.total_seconds())
                ),
                "progress_started_at": _iso(_to_utc(task.created_at)),
                "title": task.title,
                "description": strategy.warning_reason if strategy else None,
                "entity_type": "task",
                "entity_id": task.id,
                "occurred_at": _iso(actual_due_at),
            }
        )
    return items


def _task_urgency_window(
    task: Task,
    strategy: TaskReminderStrategy | None,
    now: datetime,
) -> timedelta:
    due_at = _to_utc(task.due_at)
    if due_at is None:
        return timedelta(0)
    for remind_at in (
        _to_utc(task.remind_at),
        _to_utc(strategy.ai_suggested_remind_at if strategy else None),
    ):
        if remind_at is not None and remind_at < due_at:
            return due_at - remind_at

    preparation_days = strategy.preparation_window_days if strategy else None
    if preparation_days is not None:
        return (
            timedelta(days=preparation_days)
            if preparation_days > 0
            else timedelta(hours=2)
        )

    remaining = max(due_at - now, timedelta(0))
    text = f"{task.title}\n{task.description or ''}"
    if any(keyword in text for keyword in ("火车", "高铁", "航班", "飞机", "体检", "预约")):
        return timedelta(hours=1)
    if any(keyword in text for keyword in ("项目", "总结", "报告", "周报", "提交")):
        return (
            timedelta(days=3)
            if remaining >= timedelta(days=3)
            else max(timedelta(hours=2), remaining)
        )
    if any(keyword in text for keyword in ("回复", "确认", "缴费", "支付", "购买")):
        return timedelta(minutes=15)
    if remaining >= timedelta(days=7):
        return timedelta(days=2)
    if remaining >= timedelta(days=2):
        return timedelta(hours=12)
    if remaining >= timedelta(hours=6):
        return timedelta(hours=2)
    return timedelta(minutes=30)


def _task_super_urgency_window(
    task: Task,
    strategy: TaskReminderStrategy | None,
    urgency_window: timedelta,
) -> timedelta:
    if urgency_window <= timedelta(0):
        return timedelta(0)
    text = f"{task.title}\n{task.description or ''}"
    if any(keyword in text for keyword in ("火车", "高铁", "航班", "飞机")):
        return min(urgency_window, timedelta(minutes=30))
    if any(keyword in text for keyword in ("体检", "预约")):
        return min(urgency_window, timedelta(minutes=20))
    if any(keyword in text for keyword in ("项目", "总结", "报告", "周报", "提交")):
        return min(urgency_window, timedelta(hours=6))
    if any(keyword in text for keyword in ("回复", "确认", "缴费", "支付", "购买")):
        return min(urgency_window, timedelta(minutes=5))
    if strategy is not None and strategy.warning_level == "critical":
        return min(urgency_window, timedelta(hours=2))
    if urgency_window >= timedelta(days=1):
        return timedelta(hours=3)
    if urgency_window >= timedelta(hours=6):
        return timedelta(hours=1)
    if urgency_window >= timedelta(hours=2):
        return timedelta(minutes=30)
    if urgency_window >= timedelta(minutes=30):
        return timedelta(minutes=10)
    return max(timedelta(minutes=1), urgency_window / 3)


def _task_quadrant(task: Task, urgency_window: timedelta, now: datetime) -> str:
    important = task.priority in {"high", "urgent"}
    due_at = _to_utc(task.due_at)
    urgent = due_at is not None and due_at <= now + urgency_window
    if urgent and important:
        return "urgent_important"
    if urgent:
        return "urgent_not_important"
    if important:
        return "not_urgent_important"
    return "not_urgent_not_important"


def _urgency_stage_rank(
    due_at: datetime | None,
    now: datetime,
    urgency_window: timedelta,
    super_window: timedelta,
) -> int:
    if due_at is None:
        return 2
    remaining = due_at - now
    if remaining <= super_window:
        return 0
    if remaining <= urgency_window:
        return 1
    return 2


def _quadrant_rank(quadrant: str) -> int:
    return {
        "urgent_important": 0,
        "urgent_not_important": 1,
        "not_urgent_important": 2,
        "not_urgent_not_important": 3,
    }.get(quadrant, 3)


def _quadrant_level(quadrant: str) -> str:
    return {
        "urgent_important": "critical",
        "urgent_not_important": "warning",
        "not_urgent_important": "info",
        "not_urgent_not_important": "normal",
    }.get(quadrant, "normal")


def _to_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _same_utc_day(value: datetime | None, baseline: datetime) -> bool:
    normalized = _to_utc(value)
    return normalized is not None and normalized.date() == baseline.date()
