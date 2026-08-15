from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel, Field

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
    protocol_version: int = DEVICE_PROTOCOL_VERSION
    capabilities: list[DeviceCapability] = Field(default_factory=list)
    supported_tools: list[str] = Field(default_factory=list)


class DeviceDescriptor(BaseModel):
    device_id: str = Field(min_length=1)
    account_id: str = Field(min_length=1)
    display_name: str = Field(min_length=1)
    platform: str = Field(min_length=1)
    public_key: str = Field(min_length=1)
    trust_state: DeviceTrustState = DeviceTrustState.PENDING
    capability_report: DeviceCapabilityReport = Field(default_factory=DeviceCapabilityReport)
    is_default_compute_node: bool = False
