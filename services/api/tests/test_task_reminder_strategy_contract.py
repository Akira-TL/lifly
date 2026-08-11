from __future__ import annotations

from datetime import datetime, timedelta, timezone
import inspect
from typing import Any

import pytest

from app.db.models import Reminder, Task, TaskReminderStrategy
from app.modules.tasks import router as task_router
from app.modules.tasks.reminder_strategy_engine import suggest_task_reminder_strategy


def test_task_reminder_strategy_model_and_routes_exist() -> None:
    source = inspect.getsource(task_router)

    assert TaskReminderStrategy.__tablename__ == "task_reminder_strategies"
    assert Reminder.__tablename__ == "reminders"
    assert '@router.get("/reminders"' in source
    assert '@router.get("/{task_id}/reminder-strategy"' in source
    assert '@router.post("/{task_id}/reminder-strategy/generate"' in source
    assert '@router.post("/{task_id}/reminder-strategy/confirm"' in source
    assert '@router.post("/{task_id}/reminder-strategy/dismiss"' in source
    assert "confirmed_at" in source
    assert "dismissed_at" in source
    assert "task.remind_at = strategy.ai_suggested_remind_at" in source
    assert "ensure_reminder_for_strategy" in source


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


def test_task_reminder_strategy_engine_infers_preparation_window() -> None:
    now = datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    task = Task(
        id="task-camping",
        user_id="local-dev",
        title="准备周末露营",
        due_at=now + timedelta(days=3),
        priority="normal",
        task_status="todo",
        status="active",
    )

    suggestion = suggest_task_reminder_strategy(task, now=now)

    assert suggestion is not None
    assert suggestion.warning_level == "warning"
    assert suggestion.preparation_window_days == 3
    assert suggestion.ai_suggested_remind_at == now


def test_parse_datetime_accepts_iso_z_and_empty_values() -> None:
    parsed = task_router._parse_datetime("2026-07-07T12:00:00Z")

    assert parsed == datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    assert task_router._parse_datetime(None) is None
    assert task_router._parse_datetime("") is None


class _FakeSession:
    def __init__(self) -> None:
        self.commit_count = 0
        self.refresh_count = 0

    def add(self, _item: Any) -> None:
        return None

    async def commit(self) -> None:
        self.commit_count += 1

    async def refresh(self, _item: Any) -> None:
        self.refresh_count += 1


@pytest.mark.anyio
async def test_confirm_existing_strategy_applies_manual_time_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    old_time = datetime(2026, 8, 12, 8, tzinfo=timezone.utc)
    manual_time = datetime(2026, 8, 12, 16, tzinfo=timezone.utc)
    task = Task(
        id="task-manual-reminder",
        user_id="local-dev",
        title="手动提醒任务",
        priority="normal",
        task_status="todo",
        status="active",
        remind_at=old_time,
        revision=2,
    )
    strategy = TaskReminderStrategy(
        id="strategy-existing",
        user_id="local-dev",
        task_id=task.id,
        warning_level="warning",
        warning_reason="AI 建议",
        ai_suggested_remind_at=old_time,
        strategy_status="suggested",
        source="ai",
    )
    reminder_calls: list[datetime] = []

    async def load_task(*_args: Any, **_kwargs: Any) -> Task:
        return task

    async def load_strategy(*_args: Any, **_kwargs: Any) -> TaskReminderStrategy:
        return strategy

    async def ensure_reminder(*_args: Any, **_kwargs: Any) -> None:
        reminder_calls.append(strategy.ai_suggested_remind_at)  # type: ignore[arg-type]

    monkeypatch.setattr(task_router, "_load_task", load_task)
    monkeypatch.setattr(task_router, "_load_strategy", load_strategy)
    monkeypatch.setattr(task_router, "ensure_reminder_for_strategy", ensure_reminder)
    session = _FakeSession()

    result = await task_router._upsert_strategy(
        session,  # type: ignore[arg-type]
        task.id,
        {
            "warning_level": "normal",
            "warning_reason": "用户手动设置提醒时间",
            "ai_suggested_remind_at": manual_time.isoformat(),
            "source": "user",
        },
        "confirmed",
    )

    assert result is strategy
    assert strategy.warning_level == "normal"
    assert strategy.warning_reason == "用户手动设置提醒时间"
    assert strategy.ai_suggested_remind_at == manual_time
    assert strategy.source == "user"
    assert task.remind_at == manual_time
    assert task.revision == 3
    assert reminder_calls == [manual_time]
    assert session.commit_count == 1
    assert session.refresh_count == 1
