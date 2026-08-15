from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from app.modules.account.contracts import AccountIdentity
from app.modules.devices.contracts import DeviceDescriptor, DeviceEnrollmentRequest

AUTH_PROTOCOL_VERSION = 1
AUTH_PROTOCOL = "opaque-rfc9807"


class RegistrationStartRequest(BaseModel):
    phone: str = Field(min_length=1, max_length=64)
    region: str | None = Field(default="CN", min_length=2, max_length=2)
    display_name: str | None = Field(default=None, max_length=128)
    client_request: str = Field(min_length=1)


class RegistrationFinishRequest(BaseModel):
    flow_id: str = Field(min_length=1)
    client_upload: str = Field(min_length=1)
    device: DeviceEnrollmentRequest


class LoginStartRequest(BaseModel):
    phone: str = Field(min_length=1, max_length=64)
    region: str | None = Field(default="CN", min_length=2, max_length=2)
    client_request: str = Field(min_length=1)


class LoginFinishRequest(BaseModel):
    flow_id: str = Field(min_length=1)
    client_finish: str = Field(min_length=1)
    device: DeviceEnrollmentRequest


class AuthStartResponse(BaseModel):
    protocol: Literal["opaque-rfc9807"] = AUTH_PROTOCOL
    protocol_version: Literal[1] = AUTH_PROTOCOL_VERSION
    flow_id: str
    phone_e164: str
    server_response: str
    expires_at: datetime


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class AuthSessionResponse(BaseModel):
    account: AccountIdentity
    device: DeviceDescriptor | None = None
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    access_expires_at: datetime
    refresh_expires_at: datetime


class RevokeResponse(BaseModel):
    ok: Literal[True] = True
