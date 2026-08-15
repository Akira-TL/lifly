from __future__ import annotations

from enum import StrEnum
from datetime import datetime

from pydantic import BaseModel, Field

ENCRYPTED_ENTITY_SCHEMA_VERSION = 1
PASSWORD_KEY_ENVELOPE_SCHEMA_VERSION = 1


class EncryptedEntityLifecycleStatus(StrEnum):
    ACTIVE = "active"
    TOMBSTONE = "tombstone"


class EncryptedEntityEnvelope(BaseModel):
    """Server-blind synchronized business envelope.

    ``user_id`` is injected from the authenticated Account and is not a
    client-authoritative tenant selector.
    """

    schema_version: int = ENCRYPTED_ENTITY_SCHEMA_VERSION
    id: str = Field(min_length=1)
    user_id: str = Field(min_length=1)
    entity_type: str = Field(min_length=1)
    revision: int = Field(default=1, ge=1)
    lifecycle_status: EncryptedEntityLifecycleStatus = EncryptedEntityLifecycleStatus.ACTIVE
    updated_at: datetime
    key_version: int = Field(ge=1)
    encryption_version: int = Field(default=1, ge=1)
    nonce: str = Field(min_length=1, description="Text-safe encoded AEAD nonce")
    ciphertext: str = Field(min_length=1, description="Text-safe encoded ciphertext")


class PasswordKeyEnvelope(BaseModel):
    """Password-derived wrapper around the Account Data Key; never the ADK itself."""

    schema_version: int = PASSWORD_KEY_ENVELOPE_SCHEMA_VERSION
    account_id: str = Field(min_length=1)
    key_version: int = Field(ge=1)
    encryption_version: int = Field(default=1, ge=1)
    nonce: str = Field(min_length=1)
    ciphertext: str = Field(min_length=1)
