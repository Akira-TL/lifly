from __future__ import annotations

from datetime import datetime, timedelta, timezone
import inspect

from app.db.models import Task, TaskReminderStrategy
from app.modules.tasks import router as task_router


def test_task_reminder_strategy_model_and_routes_exist() -> None:
    source = inspect.getsource(task_router)

    assert TaskReminderStrategy.__tablename__ == "task_reminder_strategies"
    assert '@router.get("/{task_id}/reminder-strategy"' in source
    assert '@router.post("/{task_id}/reminder-strategy/confirm"' in source
    assert '@router.post("/{task_id}/reminder-strategy/dismiss"' in source
    assert "confirmed_at" in source
    assert "dismissed_at" in source
    assert "task.remind_at = strategy.ai_suggested_remind_at" in source


def test_task_group_fallback_without_strategy_uses_plain_due_and_priority() -> None:
    now = datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    urgent_task = Task(
        id="task-urgent",
        user_id="local-dev",
        title="逾期任务",
        due_at=now - timedelta(hours=1),
        priority="normal",
        task_status="todo",
        status="active",
    )
    warning_task = Task(
        id="task-warning",
        user_id="local-dev",
        title="高优先级任务",
        due_at=now + timedelta(days=2),
        priority="high",
        task_status="todo",
        status="active",
    )
    done_task = Task(
        id="task-done",
        user_id="local-dev",
        title="已完成任务",
        due_at=now - timedelta(hours=1),
        priority="urgent",
        task_status="done",
        status="active",
    )

    assert task_router._task_matches_group(urgent_task, "urgent", now) is True
    assert task_router._task_matches_group(warning_task, "warning", now) is True
    assert task_router._task_matches_group(done_task, "urgent", now) is False


def test_parse_datetime_accepts_iso_z_and_empty_values() -> None:
    parsed = task_router._parse_datetime("2026-07-07T12:00:00Z")

    assert parsed == datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    assert task_router._parse_datetime(None) is None
    assert task_router._parse_datetime("") is None
