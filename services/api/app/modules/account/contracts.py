from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

ACCOUNT_CONTRACT_VERSION = 1


class AccountIdentity(BaseModel):
    """Public account identity metadata; never carries authentication or E2EE secrets."""

    schema_version: Literal[1] = ACCOUNT_CONTRACT_VERSION
    account_id: str = Field(min_length=1)
    phone_e164: str = Field(min_length=1)
    display_name: str | None = None
    account_status: str = "active"
    plan: str = "demo"
