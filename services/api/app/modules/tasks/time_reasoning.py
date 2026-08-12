from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
import re

from app.db.models import Task

MAX_AI_LEAD_SECONDS = 365 * 24 * 60 * 60
_DURATION_UNIT_PATTERN = (
    r"d|day|days|天|h|hr|hour|hours|小时|m|min|minute|minutes|分钟|分|"
    r"s|sec|second|seconds|秒"
)
_DURATION_TOKEN = re.compile(
    rf"^\s*(-?\d+(?:\.\d+)?)\s*({_DURATION_UNIT_PATTERN})\s*$",
    re.IGNORECASE,
)
_DURATION_CANDIDATE = re.compile(
    rf"(-?\d+(?:\.\d+)?)\s*({_DURATION_UNIT_PATTERN})",
    re.IGNORECASE,
)
_DURATION_UNIT_SECONDS = {
    "d": 86400,
    "day": 86400,
    "days": 86400,
    "天": 86400,
    "h": 3600,
    "hr": 3600,
    "hour": 3600,
    "hours": 3600,
    "小时": 3600,
    "m": 60,
    "min": 60,
    "minute": 60,
    "minutes": 60,
    "分钟": 60,
    "分": 60,
    "s": 1,
    "sec": 1,
    "second": 1,
    "seconds": 1,
    "秒": 1,
}


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


def extract_duration_tokens(text: str) -> tuple[str, ...]:
    return tuple(match.group(0).strip() for match in _DURATION_CANDIDATE.finditer(text))


def parse_duration_seconds(token: str) -> int:
    match = _DURATION_TOKEN.fullmatch(token)
    if match is None:
        raise ValueError("精确时长格式无效，应类似 40m、2小时、1.5h")
    try:
        amount = Decimal(match.group(1))
    except InvalidOperation as exc:
        raise ValueError("精确时长数值无效") from exc
    unit = match.group(2).lower()
    seconds = amount * _DURATION_UNIT_SECONDS[unit]
    if seconds != seconds.to_integral_value():
        raise ValueError("精确时长换算后必须是完整秒")
    value = int(seconds)
    if value < 0:
        raise ValueError("精确时长必须是非负整数秒")
    if value > MAX_AI_LEAD_SECONDS:
        raise ValueError("单个精确时长超过 31536000 秒")
    return value


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
            "模型输出后必须调用 validate；校验失败时修正输出，禁止绕过校验。",
            "无截止时间任务的两个提前量必须为 null。",
        ],
        "proposal_fields": [
            "important",
            "urgent_lead_seconds",
            "super_urgent_lead_seconds",
        ],
        "tools": {
            "lifly_time_inspect": "读取绑定任务的精确 now / DDL / remaining / overdue 与原始时长候选。",
            "lifly_time_sum_durations": "选择硬性前置耗时候选，由工具完成单位换算和求和。",
            "lifly_time_validate": "用绑定的精确时间事实与硬性耗时校验 AI 建议并计算最终阶段。",
        },
        "tool_flow": [
            "lifly_time_inspect",
            "lifly_time_sum_durations",
            "lifly_time_validate",
        ],
        "system_prompt": (
            "你是 Lifly 任务语义判断器。涉及精确时间时，不得自行进行日期、时区、时间差或单位换算。"
            "第一步必须调用 lifly_time_inspect。若 duration_candidates 非空，必须调用 "
            "lifly_time_sum_durations，并且 durations 只能从候选中选择真正影响最晚开始行动的硬性前置耗时；"
            "如果候选都不属于硬性耗时则传空数组。你只负责判断 important、urgent_lead_seconds 和 "
            "super_urgent_lead_seconds；有截止时间时两个 lead 都必须是正整数秒且 super 不得大于 urgent，"
            "无截止时间时两个 lead 必须为 null。只有 is_overdue=true 才表示 DDL 已经过期；"
            "hard_start_missed=true 只表示最安全开始时间已经错过。session 完成前禁止输出自然语言或复述工具结果，"
            "只能继续发出必需的 tool call。最后必须调用 lifly_time_validate。若返回 valid=false，读取 errors "
            "修正语义建议后再次调用 lifly_time_validate，禁止绕过校验或修改工具返回的精确事实。"
        ),
        "completion_gate": (
            "只有 time tool session 完成 valid=true 的 lifly_time_validate 后，才允许接受模型最终输出。"
        ),
        "host_policy": (
            "每一轮只向模型暴露 session.required_tool_name 对应的一个 tool schema；"
            "session 未完成时忽略自然语言最终输出，并用 continuation_prompt 要求继续工具调用。"
        ),
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
