from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, model_validator

from app.modules.crypto.contracts import EncryptedEntityEnvelope


SyncEntityType = Literal[
    "memo",
    "task",
    "expense",
    "ledger_budget",
    "reminder",
    "capture_session",
    "capture_turn",
]
SyncOperation = Literal["upsert", "delete"]


class SyncChange(BaseModel):
    """Legacy plaintext sync change used only by the v0.8.x migration path."""

    entity_type: SyncEntityType
    operation: SyncOperation
    entity_id: str = Field(min_length=1, max_length=128)
    user_id: str = Field(default="local-dev", min_length=1, max_length=128)
    revision: int = Field(ge=1)
    created_at: datetime | None = None
    updated_at: datetime
    deleted_at: datetime | None = None
    source: str = Field(default="powersync", max_length=32)
    data: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_delete_marker(self) -> "SyncChange":
        if self.operation == "delete" and self.deleted_at is None:
            raise ValueError("deleted_at is required for delete changes")
        return self


class SyncPushRequest(BaseModel):
    """Legacy plaintext push request retained for local-data migration only."""

    client_id: str = Field(min_length=1, max_length=128)
    changes: list[SyncChange] = Field(min_length=1, max_length=100)


class SyncApplyResult(BaseModel):
    entity_type: str
    entity_id: str
    operation: str
    status: Literal["applied", "skipped"]
    revision: int | None = None
    reason: str | None = None


class SyncPushResponse(BaseModel):
    applied: int
    skipped: int
    results: list[SyncApplyResult]


class EncryptedSyncPushRequest(BaseModel):
    """Opaque E2EE sync upload.

    The envelope's ``user_id`` is validated against the authenticated Account
    and the persisted tenant value is always taken from that authenticated
    subject rather than trusted from request data.
    """

    client_id: str = Field(min_length=1, max_length=128)
    changes: list[EncryptedEntityEnvelope] = Field(min_length=1, max_length=100)


class PowerSyncCredentialsResponse(BaseModel):
    endpoint: str
    token: str
    user_id: str
    device_id: str
    expires_at: datetime
    mode: Literal["authenticated"] = "authenticated"
