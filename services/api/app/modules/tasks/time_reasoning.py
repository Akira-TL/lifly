from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from app.db.models import Task

MAX_AI_LEAD_SECONDS = 365 * 24 * 60 * 60


@dataclass(frozen=True)
class TaskTimeFacts:
    now_utc: datetime
    due_at_utc: datetime | None
    remaining_seconds: int | None
    is_overdue: bool

    @property
    def has_deadline(self) -> bool:
        return self.due_at_utc is not None

    def to_ai_payload(self) -> dict[str, object | None]:
        return {
            "tool_version": "lifly.task_time_reasoning.v1",
            "has_deadline": self.has_deadline,
            "now_utc": self.now_utc.isoformat(),
            "due_at_utc": self.due_at_utc.isoformat() if self.due_at_utc else None,
            "remaining_seconds": self.remaining_seconds,
            "is_overdue": self.is_overdue,
        }


@dataclass(frozen=True)
class AiTaskTimingProposal:
    important: bool
    urgent_lead_seconds: int | None
    super_urgent_lead_seconds: int | None


@dataclass(frozen=True)
class AiTaskTimingValidation:
    valid: bool
    errors: tuple[str, ...]
    stage: str | None
    urgent_start_at_utc: datetime | None
    super_urgent_start_at_utc: datetime | None


def build_task_time_facts(task: Task, *, now: datetime) -> TaskTimeFacts:
    now_utc = _to_utc(now)
    due_at_utc = _to_utc(task.due_at)
    remaining_seconds = None
    if due_at_utc is not None:
        remaining_seconds = int((due_at_utc - now_utc).total_seconds())
    return TaskTimeFacts(
        now_utc=now_utc,
        due_at_utc=due_at_utc,
        remaining_seconds=remaining_seconds,
        is_overdue=remaining_seconds is not None and remaining_seconds < 0,
    )


def validate_ai_task_timing(
    facts: TaskTimeFacts,
    proposal: AiTaskTimingProposal,
) -> AiTaskTimingValidation:
    errors: list[str] = []
    urgent = proposal.urgent_lead_seconds
    super_urgent = proposal.super_urgent_lead_seconds

    if not facts.has_deadline:
        if urgent is not None or super_urgent is not None:
            errors.append("无截止时间任务不得生成紧急时间窗口")
        return AiTaskTimingValidation(
            valid=not errors,
            errors=tuple(errors),
            stage="no_deadline" if not errors else None,
            urgent_start_at_utc=None,
            super_urgent_start_at_utc=None,
        )

    if not _is_valid_lead(urgent):
        errors.append("urgent_lead_seconds 必须是 1 到 31536000 的整数秒")
    if not _is_valid_lead(super_urgent):
        errors.append("super_urgent_lead_seconds 必须是 1 到 31536000 的整数秒")
    if (
        _is_valid_lead(urgent)
        and _is_valid_lead(super_urgent)
        and super_urgent > urgent
    ):
        errors.append("super_urgent_lead_seconds 必须小于等于 urgent_lead_seconds")

    if errors:
        return AiTaskTimingValidation(
            valid=False,
            errors=tuple(errors),
            stage=None,
            urgent_start_at_utc=None,
            super_urgent_start_at_utc=None,
        )

    assert facts.due_at_utc is not None
    assert facts.remaining_seconds is not None
    assert urgent is not None
    assert super_urgent is not None
    urgent_start = facts.due_at_utc - timedelta(seconds=urgent)
    super_start = facts.due_at_utc - timedelta(seconds=super_urgent)

    if facts.remaining_seconds < 0:
        stage = "overdue"
    elif facts.remaining_seconds <= super_urgent:
        stage = "super_urgent"
    elif facts.remaining_seconds <= urgent:
        stage = "urgent"
    else:
        stage = "not_urgent"

    return AiTaskTimingValidation(
        valid=True,
        errors=(),
        stage=stage,
        urgent_start_at_utc=urgent_start,
        super_urgent_start_at_utc=super_start,
    )


def task_time_ai_contract() -> dict[str, object]:
    return {
        "version": "lifly.task_time_reasoning.v1",
        "rules": [
            "精确时间计算必须使用 time_facts，不得由模型自行做日期或时区算术。",
            "模型只估计重要性以及两个提前量，提前量统一使用整数秒。",
            "模型输出后必须调用 timing_validation；校验失败时修正输出，禁止绕过校验。",
            "无截止时间任务的两个提前量必须为 null。",
        ],
        "proposal_fields": [
            "important",
            "urgent_lead_seconds",
            "super_urgent_lead_seconds",
        ],
        "validation_required": True,
    }


def _is_valid_lead(value: int | None) -> bool:
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and 0 < value <= MAX_AI_LEAD_SECONDS
    )


def _to_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
