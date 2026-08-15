from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, Field

AI_JOB_PROTOCOL_VERSION = 1


class AiJobMessageType(StrEnum):
    REQUEST = "request"
    RESULT = "result"


class AiJobEnvelope(BaseModel):
    """Opaque device-to-device AI relay envelope.

    Result messages use ``correlation_id`` to reference the request job. The
    cloud may route and expire this envelope but must never receive plaintext
    job content or a key capable of decrypting ``ciphertext``.
    """

    protocol_version: int = AI_JOB_PROTOCOL_VERSION
    job_id: str = Field(min_length=1)
    account_id: str = Field(min_length=1)
    source_device_id: str = Field(min_length=1)
    target_device_id: str = Field(min_length=1)
    message_type: AiJobMessageType = AiJobMessageType.REQUEST
    correlation_id: str | None = None
    idempotency_key: str = Field(min_length=1)
    expires_at: datetime
    encryption_version: int = Field(default=1, ge=1)
    nonce: str = Field(min_length=1, description="Text-safe encoded device-envelope nonce")
    ciphertext: str = Field(min_length=1, description="Text-safe encoded job payload")
