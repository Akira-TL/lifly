from __future__ import annotations

from datetime import datetime, timedelta, timezone
import inspect
import json
from typing import Any

import pytest

from app.db.models import Reminder, Task, TaskReminderStrategy
from app.modules.tasks import router as task_router
from app.modules.tasks.reminder_strategy_engine import suggest_task_reminder_strategy
from app.modules.tasks.time_reasoning import (
    AiTaskTimingProposal,
    build_task_time_facts,
    parse_duration_seconds,
    sum_duration_seconds,
    task_time_ai_contract,
    validate_ai_task_timing,
)
from app.modules.tasks.time_reasoning_cli import main as time_reasoning_cli_main
from app.modules.tasks.time_reasoning_tools import (
    TaskTimeToolSession,
    task_time_tool_definitions,
)


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
        task.user_id,
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


def test_time_facts_do_exact_datetime_math_for_ai() -> None:
    china = timezone(timedelta(hours=8))
    now = datetime(2026, 8, 11, 23, 9, tzinfo=china)
    due_at = datetime(2026, 8, 12, 8, 30, tzinfo=china)
    task = Task(
        id="task-time-reasoning",
        user_id="local-dev",
        title="赶高铁去外地开会",
        description="提前到站并完成安检",
        due_at=due_at,
        priority="high",
        task_status="todo",
        status="active",
    )

    facts = build_task_time_facts(task, now=now)

    assert facts.has_deadline is True
    assert facts.remaining_seconds == 9 * 3600 + 21 * 60
    assert facts.is_overdue is False
    assert facts.now_utc.isoformat() == "2026-08-11T15:09:00+00:00"
    assert facts.due_at_utc is not None
    assert facts.due_at_utc.isoformat() == "2026-08-12T00:30:00+00:00"
    assert facts.to_ai_payload()["remaining_seconds"] == 33660


def test_ai_timing_validation_derives_absolute_thresholds_and_stage() -> None:
    china = timezone(timedelta(hours=8))
    due_at = datetime(2026, 8, 12, 8, 30, tzinfo=china)
    task = Task(
        id="task-time-validation",
        user_id="local-dev",
        title="赶高铁去外地开会",
        due_at=due_at,
        priority="high",
        task_status="todo",
        status="active",
    )
    facts = build_task_time_facts(
        task,
        now=datetime(2026, 8, 12, 8, 10, tzinfo=china),
    )

    validation = validate_ai_task_timing(
        facts,
        AiTaskTimingProposal(
            important=True,
            urgent_lead_seconds=3600,
            super_urgent_lead_seconds=1800,
        ),
    )

    assert validation.valid is True
    assert validation.errors == ()
    assert validation.stage == "super_urgent"
    assert validation.urgent_start_at_utc is not None
    assert validation.urgent_start_at_utc.isoformat() == "2026-08-11T23:30:00+00:00"
    assert validation.super_urgent_start_at_utc is not None
    assert validation.super_urgent_start_at_utc.isoformat() == "2026-08-12T00:00:00+00:00"


def test_ai_timing_validation_rejects_invalid_windows_and_deadline_invention() -> None:
    china = timezone(timedelta(hours=8))
    task = Task(
        id="task-invalid-time",
        user_id="local-dev",
        title="普通任务",
        due_at=datetime(2026, 8, 12, 8, 30, tzinfo=china),
        priority="normal",
        task_status="todo",
        status="active",
    )
    with_deadline = build_task_time_facts(
        task,
        now=datetime(2026, 8, 11, 23, 9, tzinfo=china),
    )
    invalid_order = validate_ai_task_timing(
        with_deadline,
        AiTaskTimingProposal(
            important=True,
            urgent_lead_seconds=1800,
            super_urgent_lead_seconds=3600,
        ),
    )
    assert invalid_order.valid is False
    assert "super_urgent_lead_seconds 必须小于等于 urgent_lead_seconds" in invalid_order.errors

    task.due_at = None
    without_deadline = build_task_time_facts(task, now=with_deadline.now_utc)
    invented_deadline = validate_ai_task_timing(
        without_deadline,
        AiTaskTimingProposal(
            important=False,
            urgent_lead_seconds=600,
            super_urgent_lead_seconds=300,
        ),
    )
    assert invented_deadline.valid is False
    assert "无截止时间任务不得生成紧急时间窗口" in invented_deadline.errors


def test_ai_time_contract_forbids_model_datetime_arithmetic() -> None:
    contract = task_time_ai_contract()

    assert contract["version"] == "lifly.task_time_reasoning.v1"
    assert contract["rules"][0] == "精确时间计算必须使用 time_facts，不得由模型自行做日期或时区算术。"
    assert contract["proposal_fields"] == [
        "important",
        "urgent_lead_seconds",
        "super_urgent_lead_seconds",
    ]
    assert contract["tool_flow"] == [
        "lifly_time_inspect",
        "lifly_time_sum_durations",
        "lifly_time_validate",
    ]
    assert "不得自行进行日期、时区、时间差或单位换算" in contract["system_prompt"]
    assert "lifly_time_validate" in contract["system_prompt"]
    assert "有截止时间时两个 lead 都必须是正整数秒" in contract["system_prompt"]
    assert "只有 is_overdue=true 才表示 DDL 已经过期" in contract["system_prompt"]
    assert "session 完成前禁止输出自然语言" in contract["system_prompt"]
    assert contract["completion_gate"] == (
        "只有 time tool session 完成 valid=true 的 lifly_time_validate 后，才允许接受模型最终输出。"
    )
    assert "session.required_tool_name" in contract["host_policy"]
    assert contract["validation_required"] is True


def test_time_reasoning_cli_inspects_and_validates_without_model_math(
    capsys: pytest.CaptureFixture[str],
) -> None:
    exit_code = time_reasoning_cli_main(
        [
            "inspect",
            "--now",
            "2026-08-11T23:09:00+08:00",
            "--due-at",
            "2026-08-12T08:30:00+08:00",
        ]
    )
    inspected = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert inspected["remaining_seconds"] == 33660
    assert inspected["is_overdue"] is False

    exit_code = time_reasoning_cli_main(
        ["sum-durations", "--duration", "40m", "20m"]
    )
    summed = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert summed["parts_seconds"] == [2400, 1200]
    assert summed["total_seconds"] == 3600

    exit_code = time_reasoning_cli_main(
        ["sum-durations", "--duration=-1m"]
    )
    rejected_sum = json.loads(capsys.readouterr().out)
    assert exit_code == 0
    assert rejected_sum == {
        "valid": False,
        "errors": ["精确时长必须是非负整数秒"],
    }

    exit_code = time_reasoning_cli_main(
        [
            "validate",
            "--now",
            "2026-08-12T08:10:00+08:00",
            "--due-at",
            "2026-08-12T08:30:00+08:00",
            "--important",
            "true",
            "--urgent-lead-seconds",
            "3600",
            "--super-urgent-lead-seconds",
            "1800",
        ]
    )
    validated = json.loads(capsys.readouterr().out)

    assert exit_code == 0
    assert validated["valid"] is True
    assert validated["stage"] == "super_urgent"
    assert validated["urgent_start_at_utc"] == "2026-08-11T23:30:00+00:00"


def test_time_tool_session_forces_exact_duration_check_before_validation() -> None:
    china = timezone(timedelta(hours=8))
    task = Task(
        id="task-tool-session",
        user_id="local-dev",
        title="08:30 赶高铁去外地开会",
        description="到车站路程约40分钟，至少提前20分钟进站。",
        due_at=datetime(2026, 8, 12, 8, 30, tzinfo=china),
        priority="high",
        task_status="todo",
        status="active",
    )
    session = TaskTimeToolSession.for_task(
        task,
        now=datetime(2026, 8, 12, 7, 35, tzinfo=china),
    )
    assert session.is_complete is False
    assert session.required_tool_name == "lifly_time_inspect"

    before_inspect = session.execute(
        "lifly_time_validate",
        {
            "important": True,
            "urgent_lead_seconds": 3600,
            "super_urgent_lead_seconds": 1200,
        },
    )
    assert before_inspect == {
        "valid": False,
        "errors": ["必须先调用 lifly_time_inspect"],
    }

    inspected = session.execute("lifly_time_inspect", {})
    assert inspected["valid"] is True
    assert inspected["remaining_seconds"] == 3300
    assert inspected["duration_candidates"] == ["40分钟", "20分钟"]
    assert session.required_tool_name == "lifly_time_sum_durations"

    premature = session.execute(
        "lifly_time_validate",
        {
            "important": True,
            "urgent_lead_seconds": 1800,
            "super_urgent_lead_seconds": 1200,
        },
    )
    assert premature == {
        "valid": False,
        "errors": ["检测到明确时长，必须先调用 lifly_time_sum_durations"],
    }

    invented = session.execute(
        "lifly_time_sum_durations",
        {"durations": ["3小时"]},
    )
    assert invented == {
        "valid": False,
        "errors": ["3小时 不在任务的精确时长候选中"],
    }

    summed = session.execute(
        "lifly_time_sum_durations",
        {"durations": ["40分钟", "20分钟"]},
    )
    assert summed["valid"] is True
    assert summed["parts_seconds"] == [2400, 1200]
    assert summed["minimum_urgent_lead_seconds"] == 3600
    assert summed["hard_start_missed"] is True
    assert session.required_tool_name == "lifly_time_validate"

    underestimated = session.execute(
        "lifly_time_validate",
        {
            "important": True,
            "urgent_lead_seconds": 1800,
            "super_urgent_lead_seconds": 1200,
        },
    )
    assert underestimated["valid"] is False
    assert underestimated["errors"] == [
        "urgent_lead_seconds 小于精确时间约束 3600 秒"
    ]
    assert session.required_tool_name == "lifly_time_validate"
    assert "lifly_time_validate" in session.continuation_prompt()

    repaired = session.execute(
        "lifly_time_validate",
        {
            "important": True,
            "urgent_lead_seconds": 3600,
            "super_urgent_lead_seconds": 1200,
        },
    )
    assert repaired["valid"] is True
    assert repaired["stage"] == "urgent"
    assert repaired["minimum_urgent_lead_seconds"] == 3600
    assert session.is_complete is True
    assert session.required_tool_name is None


def test_time_tool_definitions_are_provider_neutral_function_schemas() -> None:
    definitions = task_time_tool_definitions()

    assert [item["function"]["name"] for item in definitions] == [
        "lifly_time_inspect",
        "lifly_time_sum_durations",
        "lifly_time_validate",
    ]
    for item in definitions:
        assert item["type"] == "function"
        assert item["function"]["parameters"]["type"] == "object"


def test_exact_duration_evidence_blocks_ai_underestimation() -> None:
    assert parse_duration_seconds("1d") == 86400
    assert parse_duration_seconds("3h") == 10800
    assert parse_duration_seconds("40m") == 2400
    assert parse_duration_seconds("40分钟") == 2400
    assert parse_duration_seconds("1.5h") == 5400
    assert parse_duration_seconds("15s") == 15
    exact_minimum = sum_duration_seconds([
        parse_duration_seconds("40m"),
        parse_duration_seconds("20m"),
    ])
    task = Task(
        id="task-exact-duration",
        user_id="local-dev",
        title="赶高铁",
        due_at=datetime(2026, 8, 12, 8, 30, tzinfo=timezone(timedelta(hours=8))),
        priority="high",
        task_status="todo",
        status="active",
    )
    facts = build_task_time_facts(
        task,
        now=datetime(2026, 8, 12, 7, 35, tzinfo=timezone(timedelta(hours=8))),
    )

    validation = validate_ai_task_timing(
        facts,
        AiTaskTimingProposal(
            important=True,
            urgent_lead_seconds=1800,
            super_urgent_lead_seconds=1200,
        ),
        minimum_urgent_lead_seconds=exact_minimum,
    )

    assert exact_minimum == 3600
    assert validation.valid is False
    assert "urgent_lead_seconds 小于精确时间约束 3600 秒" in validation.errors
