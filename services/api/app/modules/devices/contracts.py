from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field, model_validator

DEVICE_PROTOCOL_VERSION = 1


class DeviceCapability(StrEnum):
    LOCAL_AI = "local_ai"
    LOCAL_MCP = "local_mcp"
    BACKGROUND_EXECUTOR = "background_executor"


class DeviceTrustState(StrEnum):
    PENDING = "pending"
    TRUSTED = "trusted"
    REVOKED = "revoked"


class DeviceCapabilityReport(BaseModel):
    protocol_version: Literal[1] = DEVICE_PROTOCOL_VERSION
    capabilities: list[DeviceCapability] = Field(default_factory=list)
    supported_tools: list[str] = Field(default_factory=list)


class DeviceEnrollmentRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=64)
    display_name: str = Field(min_length=1, max_length=128)
    platform: str = Field(min_length=1, max_length=32)
    public_key: str = Field(min_length=1)
    capability_report: DeviceCapabilityReport = Field(default_factory=DeviceCapabilityReport)
    make_default_compute_node: bool = False

    @model_validator(mode="after")
    def validate_default_compute_node(self) -> "DeviceEnrollmentRequest":
        if self.make_default_compute_node and not self.capability_report.capabilities:
            raise ValueError("Default Compute Node must report a compute capability")
        return self


class DeviceUpdateRequest(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=128)


class DeviceHeartbeatRequest(BaseModel):
    capability_report: DeviceCapabilityReport


class DeviceDescriptor(BaseModel):
    device_id: str = Field(min_length=1)
    account_id: str = Field(min_length=1)
    display_name: str = Field(min_length=1)
    platform: str = Field(min_length=1)
    public_key: str = Field(min_length=1)
    trust_state: DeviceTrustState = DeviceTrustState.PENDING
    capability_report: DeviceCapabilityReport = Field(default_factory=DeviceCapabilityReport)
    is_default_compute_node: bool = False
    last_seen_at: datetime | None = None
    revoked_at: datetime | None = None
    key_version: int = Field(default=1, ge=1)
    protocol_version: Literal[1] = DEVICE_PROTOCOL_VERSION


class DeviceListResponse(BaseModel):
    devices: list[DeviceDescriptor]


class DeviceRevokeResponse(BaseModel):
    device: DeviceDescriptor
    revoked_sessions: int = Field(ge=0)
