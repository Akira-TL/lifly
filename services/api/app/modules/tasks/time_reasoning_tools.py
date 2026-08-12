from __future__ import annotations

from collections import Counter
from collections.abc import Mapping
from dataclasses import dataclass
from datetime import datetime

from app.db.models import Task
from app.modules.tasks.time_reasoning import (
    AiTaskTimingProposal,
    TaskTimeFacts,
    build_task_time_facts,
    extract_duration_tokens,
    parse_duration_seconds,
    sum_duration_seconds,
    validate_ai_task_timing,
)

_INSPECT_TOOL = "lifly_time_inspect"
_SUM_TOOL = "lifly_time_sum_durations"
_VALIDATE_TOOL = "lifly_time_validate"


@dataclass
class TaskTimeToolSession:
    facts: TaskTimeFacts
    duration_candidates: tuple[str, ...]
    _inspected: bool = False
    _duration_check_completed: bool = False
    _minimum_urgent_lead_seconds: int | None = None
    _validation_complete: bool = False

    @classmethod
    def for_task(cls, task: Task, *, now: datetime) -> "TaskTimeToolSession":
        text = f"{task.title or ''}\n{task.description or ''}"
        candidates = extract_duration_tokens(text)
        return cls(
            facts=build_task_time_facts(task, now=now),
            duration_candidates=candidates,
            _duration_check_completed=not candidates,
        )

    @property
    def is_complete(self) -> bool:
        return self._validation_complete

    @property
    def required_tool_name(self) -> str | None:
        if self._validation_complete:
            return None
        if not self._inspected:
            return _INSPECT_TOOL
        if self.duration_candidates and not self._duration_check_completed:
            return _SUM_TOOL
        return _VALIDATE_TOOL

    def continuation_prompt(self) -> str:
        required = self.required_tool_name
        if required is None:
            return ""
        return (
            f"时间推理流程尚未完成。现在必须调用 {required}，不要输出最终解释；"
            "若工具返回 valid=false，按 errors 修正后继续调用必需工具。"
        )

    def execute(
        self,
        name: str,
        arguments: Mapping[str, object],
    ) -> dict[str, object | None]:
        try:
            if name == _INSPECT_TOOL:
                return self._inspect()
            if name == _SUM_TOOL:
                return self._sum_durations(arguments)
            if name == _VALIDATE_TOOL:
                return self._validate(arguments)
            raise ValueError(f"未知时间工具：{name}")
        except (TypeError, ValueError) as exc:
            return {"valid": False, "errors": [str(exc)]}

    def _inspect(self) -> dict[str, object | None]:
        self._inspected = True
        return {
            "valid": True,
            **self.facts.to_ai_payload(),
            "duration_candidates": list(self.duration_candidates),
            "duration_check_required": bool(self.duration_candidates),
        }

    def _sum_durations(
        self,
        arguments: Mapping[str, object],
    ) -> dict[str, object | None]:
        if not self._inspected:
            raise ValueError("必须先调用 lifly_time_inspect")
        durations = _require_string_list(arguments, "durations")
        _ensure_selected_candidates(durations, self.duration_candidates)
        parts_seconds = [parse_duration_seconds(token) for token in durations]
        total = sum_duration_seconds(parts_seconds)
        self._duration_check_completed = True
        self._minimum_urgent_lead_seconds = total if total > 0 else None
        self._validation_complete = False
        hard_start_missed = (
            self.facts.remaining_seconds is not None
            and total > self.facts.remaining_seconds
        )
        return {
            "valid": True,
            "durations": durations,
            "parts_seconds": parts_seconds,
            "minimum_urgent_lead_seconds": total,
            "hard_start_missed": hard_start_missed,
        }

    def _validate(
        self,
        arguments: Mapping[str, object],
    ) -> dict[str, object | None]:
        if not self._inspected:
            return {
                "valid": False,
                "errors": ["必须先调用 lifly_time_inspect"],
            }
        if self.duration_candidates and not self._duration_check_completed:
            return {
                "valid": False,
                "errors": ["检测到明确时长，必须先调用 lifly_time_sum_durations"],
            }
        proposal = AiTaskTimingProposal(
            important=_require_bool(arguments, "important"),
            urgent_lead_seconds=_optional_int(arguments, "urgent_lead_seconds"),
            super_urgent_lead_seconds=_optional_int(
                arguments,
                "super_urgent_lead_seconds",
            ),
        )
        validation = validate_ai_task_timing(
            self.facts,
            proposal,
            minimum_urgent_lead_seconds=self._minimum_urgent_lead_seconds,
        )
        self._validation_complete = validation.valid
        return {
            "valid": validation.valid,
            "errors": list(validation.errors),
            "stage": validation.stage,
            "minimum_urgent_lead_seconds": self._minimum_urgent_lead_seconds or 0,
            "urgent_start_at_utc": _iso(validation.urgent_start_at_utc),
            "super_urgent_start_at_utc": _iso(validation.super_urgent_start_at_utc),
        }


def task_time_tool_definitions() -> list[dict[str, object]]:
    nullable_integer = {
        "anyOf": [
            {"type": "integer", "minimum": 1, "maximum": 31536000},
            {"type": "null"},
        ]
    }
    return [
        {
            "type": "function",
            "function": {
                "name": _INSPECT_TOOL,
                "description": (
                    "读取当前任务的精确时间事实。涉及日期、时区、剩余时间时必须先调用。"
                ),
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "additionalProperties": False,
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": _SUM_TOOL,
                "description": (
                    "从 inspect 给出的 duration_candidates 中选择属于硬性前置耗时的项，"
                    "由工具完成单位换算和求和。候选存在时必须调用，即使选择为空数组。"
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "durations": {
                            "type": "array",
                            "items": {"type": "string"},
                        }
                    },
                    "required": ["durations"],
                    "additionalProperties": False,
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": _VALIDATE_TOOL,
                "description": (
                    "提交 AI 的重要性与紧急提前量建议；工具用绑定的精确时间事实和"
                    "硬性耗时约束校验并计算最终阶段。校验失败必须修正后再次调用。"
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "important": {"type": "boolean"},
                        "urgent_lead_seconds": nullable_integer,
                        "super_urgent_lead_seconds": nullable_integer,
                    },
                    "required": [
                        "important",
                        "urgent_lead_seconds",
                        "super_urgent_lead_seconds",
                    ],
                    "additionalProperties": False,
                },
            },
        },
    ]


def _ensure_selected_candidates(
    selected: list[str],
    candidates: tuple[str, ...],
) -> None:
    available = Counter(candidates)
    used: Counter[str] = Counter()
    for token in selected:
        used[token] += 1
        if used[token] > available[token]:
            raise ValueError(f"{token} 不在任务的精确时长候选中")


def _require_string_list(
    arguments: Mapping[str, object],
    key: str,
) -> list[str]:
    value = arguments.get(key)
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise TypeError(f"{key} 必须是字符串数组")
    return list(value)


def _require_bool(arguments: Mapping[str, object], key: str) -> bool:
    value = arguments.get(key)
    if not isinstance(value, bool):
        raise TypeError(f"{key} 必须是布尔值")
    return value


def _optional_int(arguments: Mapping[str, object], key: str) -> int | None:
    value = arguments.get(key)
    if value is None:
        return None
    if not isinstance(value, int) or isinstance(value, bool):
        raise TypeError(f"{key} 必须是整数或 null")
    return value


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None
