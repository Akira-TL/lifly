from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, JsonValue, field_validator


class CaptureParseRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20_000)
    timezone: str = Field(default="Asia/Shanghai", min_length=1, max_length=64)
    locale: str = Field(default="zh-CN", min_length=1, max_length=16)
    asset_ids: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("text")
    @classmethod
    def normalize_text(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError("text is required")
        return text


class CaptureAppendTurnRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20_000)
    asset_ids: list[str] = Field(default_factory=list, max_length=20)

    @field_validator("text")
    @classmethod
    def normalize_text(cls, value: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError("text is required")
        return text


class CaptureCommitRequest(BaseModel):
    capture_id: str = Field(min_length=1, max_length=128)
    turn_id: str | None = Field(default=None, min_length=1, max_length=128)
    selected_action_indexes: list[int] | None = Field(default=None, max_length=10)
    source_text: str | None = Field(default=None, max_length=20_000)
    request_id: str | None = Field(default=None, max_length=64)

    @field_validator("selected_action_indexes")
    @classmethod
    def validate_indexes(cls, value: list[int] | None) -> list[int] | None:
        if value is None:
            return None
        if any(index < 0 for index in value):
            raise ValueError("selected_action_indexes must be non-negative")
        if len(set(value)) != len(value):
            raise ValueError("selected_action_indexes must be unique")
        return value


class CaptureReviseActionRequest(BaseModel):
    action_index: int = Field(ge=0)
    action_type: Literal["memo_create", "task_create", "expense_create"] | None = None
    payload: dict[str, JsonValue]
    confidence: float | None = Field(default=None, ge=0, le=1)
    note: str | None = Field(default=None, max_length=2_000)


class CaptureDismissRequest(BaseModel):
    reason: str | None = Field(default=None, max_length=2_000)
