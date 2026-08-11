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


def build_time_facts(*, now: datetime, due_at: datetime | None) -> TaskTimeFacts:
    now_utc = _to_utc(now)
    due_at_utc = _to_utc(due_at)
    remaining_seconds = None
    if due_at_utc is not None:
        remaining_seconds = int((due_at_utc - now_utc).total_seconds())
    return TaskTimeFacts(
        now_utc=now_utc,
        due_at_utc=due_at_utc,
        remaining_seconds=remaining_seconds,
        is_overdue=remaining_seconds is not None and remaining_seconds < 0,
    )


def build_task_time_facts(task: Task, *, now: datetime) -> TaskTimeFacts:
    return build_time_facts(now=now, due_at=task.due_at)


def sum_duration_seconds(parts_seconds: list[int] | tuple[int, ...]) -> int:
    total = 0
    for value in parts_seconds:
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError("精确时长必须是非负整数秒")
        total += value
    if total > MAX_AI_LEAD_SECONDS:
        raise ValueError("精确时长总和超过 31536000 秒")
    return total


def validate_ai_task_timing(
    facts: TaskTimeFacts,
    proposal: AiTaskTimingProposal,
    *,
    minimum_urgent_lead_seconds: int | None = None,
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
    if minimum_urgent_lead_seconds is not None:
        if not _is_valid_lead(minimum_urgent_lead_seconds):
            errors.append("minimum_urgent_lead_seconds 必须是 1 到 31536000 的整数秒")
        elif _is_valid_lead(urgent) and urgent < minimum_urgent_lead_seconds:
            errors.append(
                f"urgent_lead_seconds 小于精确时间约束 {minimum_urgent_lead_seconds} 秒"
            )

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
            "任务文本包含明确时长时，必须先用 sum_durations 做精确加总，并把结果作为最小紧急提前量交给 validate。",
            "模型输出后必须调用 timing_validation；校验失败时修正输出，禁止绕过校验。",
            "无截止时间任务的两个提前量必须为 null。",
        ],
        "proposal_fields": [
            "important",
            "urgent_lead_seconds",
            "super_urgent_lead_seconds",
        ],
        "tools": {
            "inspect": "计算 now / DDL / remaining_seconds / overdue，禁止模型自行做日期算术。",
            "sum_durations": "对任务文本中明确给出的多个耗时做精确整数秒加总。",
            "validate": "校验 AI 提前量与精确最小时长，并计算 urgent_start / super_start / 当前阶段。",
        },
        "tool_flow": [
            "inspect",
            "sum_exact_durations_when_present",
            "semantic_proposal",
            "validate",
            "retry_on_validation_error",
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
