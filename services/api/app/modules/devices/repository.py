from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Protocol

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Device
from app.modules.devices.contracts import (
    DeviceCapability,
    DeviceCapabilityReport,
    DeviceTrustState,
)

_TOOL_PREFIX = "tool:"


class DeviceNotFound(LookupError):
    pass


class DeviceOwnershipConflict(RuntimeError):
    pass


class DeviceNotTrusted(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class DeviceRecord:
    device_id: str
    account_id: str
    display_name: str
    platform: str
    public_key: str
    trust_state: DeviceTrustState
    capability_report: DeviceCapabilityReport
    is_default_compute_node: bool
    last_seen_at: datetime | None
    revoked_at: datetime | None
    key_version: int
    protocol_version: int

    @classmethod
    def from_model(cls, device: Device) -> "DeviceRecord":
        return cls(
            device_id=device.id,
            account_id=device.account_id,
            display_name=device.display_name,
            platform=device.platform,
            public_key=device.public_key,
            trust_state=DeviceTrustState(device.trust_state),
            capability_report=_decode_capability_report(device.capabilities),
            is_default_compute_node=device.is_default_compute_node,
            last_seen_at=device.last_seen_at,
            revoked_at=device.revoked_at,
            key_version=device.key_version,
            protocol_version=device.protocol_version,
        )


class DeviceRepository(Protocol):
    async def register_trusted(
        self,
        *,
        account_id: str,
        device_id: str,
        display_name: str,
        platform: str,
        public_key: str,
        capability_report: DeviceCapabilityReport,
        make_default_compute_node: bool,
    ) -> DeviceRecord: ...

    async def list_for_account(self, account_id: str) -> list[DeviceRecord]: ...

    async def get_for_account(self, account_id: str, device_id: str) -> DeviceRecord: ...

    async def rename(
        self, *, account_id: str, device_id: str, display_name: str
    ) -> DeviceRecord: ...

    async def heartbeat(
        self,
        *,
        account_id: str,
        device_id: str,
        capability_report: DeviceCapabilityReport,
    ) -> DeviceRecord: ...

    async def set_default_compute_node(
        self, *, account_id: str, device_id: str
    ) -> DeviceRecord: ...

    async def revoke(self, *, account_id: str, device_id: str) -> DeviceRecord: ...


class SqlAlchemyDeviceRepository:
    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def register_trusted(
        self,
        *,
        account_id: str,
        device_id: str,
        display_name: str,
        platform: str,
        public_key: str,
        capability_report: DeviceCapabilityReport,
        make_default_compute_node: bool,
    ) -> DeviceRecord:
        result = await self._db.execute(select(Device).where(Device.id == device_id))
        device = result.scalar_one_or_none()
        now = datetime.now(timezone.utc)
        if device is not None and device.account_id != account_id:
            raise DeviceOwnershipConflict("Device id belongs to another account")
        if device is None:
            device = Device(
                id=device_id,
                account_id=account_id,
                display_name=display_name,
                platform=platform,
                public_key=public_key,
                trust_state=DeviceTrustState.TRUSTED.value,
                capabilities=_encode_capability_report(capability_report),
                is_default_compute_node=False,
                last_seen_at=now,
            )
            self._db.add(device)
        else:
            device.display_name = display_name
            device.platform = platform
            if device.public_key != public_key:
                device.public_key = public_key
                device.key_version += 1
            device.trust_state = DeviceTrustState.TRUSTED.value
            device.capabilities = _encode_capability_report(capability_report)
            device.last_seen_at = now
            device.revoked_at = None
        await self._db.flush()
        if make_default_compute_node:
            await self._set_default_model(account_id=account_id, device=device)
        await self._db.commit()
        await self._db.refresh(device)
        return DeviceRecord.from_model(device)

    async def list_for_account(self, account_id: str) -> list[DeviceRecord]:
        result = await self._db.execute(
            select(Device).where(Device.account_id == account_id).order_by(Device.created_at)
        )
        return [DeviceRecord.from_model(item) for item in result.scalars().all()]

    async def get_for_account(self, account_id: str, device_id: str) -> DeviceRecord:
        device = await self._load(account_id=account_id, device_id=device_id)
        return DeviceRecord.from_model(device)

    async def rename(
        self, *, account_id: str, device_id: str, display_name: str
    ) -> DeviceRecord:
        device = await self._load(account_id=account_id, device_id=device_id)
        device.display_name = display_name
        await self._db.commit()
        await self._db.refresh(device)
        return DeviceRecord.from_model(device)

    async def heartbeat(
        self,
        *,
        account_id: str,
        device_id: str,
        capability_report: DeviceCapabilityReport,
    ) -> DeviceRecord:
        device = await self._load(account_id=account_id, device_id=device_id)
        if device.trust_state != DeviceTrustState.TRUSTED.value:
            raise DeviceNotTrusted("Revoked device cannot report capabilities")
        device.capabilities = _encode_capability_report(capability_report)
        device.last_seen_at = datetime.now(timezone.utc)
        await self._db.commit()
        await self._db.refresh(device)
        return DeviceRecord.from_model(device)

    async def set_default_compute_node(
        self, *, account_id: str, device_id: str
    ) -> DeviceRecord:
        device = await self._load(account_id=account_id, device_id=device_id)
        if device.trust_state != DeviceTrustState.TRUSTED.value:
            raise DeviceNotTrusted("Default Compute Node must be trusted")
        if not _decode_capability_report(device.capabilities).capabilities:
            raise DeviceNotTrusted("Default Compute Node has no compute capability")
        await self._set_default_model(account_id=account_id, device=device)
        await self._db.commit()
        await self._db.refresh(device)
        return DeviceRecord.from_model(device)

    async def revoke(self, *, account_id: str, device_id: str) -> DeviceRecord:
        device = await self._load(account_id=account_id, device_id=device_id)
        if device.trust_state != DeviceTrustState.REVOKED.value:
            device.trust_state = DeviceTrustState.REVOKED.value
            device.is_default_compute_node = False
            device.revoked_at = datetime.now(timezone.utc)
            await self._db.commit()
            await self._db.refresh(device)
        return DeviceRecord.from_model(device)

    async def _load(self, *, account_id: str, device_id: str) -> Device:
        result = await self._db.execute(
            select(Device).where(
                Device.id == device_id,
                Device.account_id == account_id,
            )
        )
        device = result.scalar_one_or_none()
        if device is None:
            raise DeviceNotFound(device_id)
        return device

    async def _set_default_model(self, *, account_id: str, device: Device) -> None:
        result = await self._db.execute(
            select(Device).where(
                Device.account_id == account_id,
                Device.is_default_compute_node.is_(True),
                Device.id != device.id,
            )
        )
        for other in result.scalars().all():
            other.is_default_compute_node = False
        await self._db.flush()
        device.is_default_compute_node = True


def _encode_capability_report(report: DeviceCapabilityReport) -> list[str]:
    values = [item.value for item in report.capabilities]
    values.extend(f"{_TOOL_PREFIX}{tool}" for tool in report.supported_tools)
    return values


def _decode_capability_report(values: list | None) -> DeviceCapabilityReport:
    capabilities = []
    supported_tools = []
    for value in values or []:
        if not isinstance(value, str):
            continue
        if value.startswith(_TOOL_PREFIX):
            tool = value[len(_TOOL_PREFIX) :]
            if tool:
                supported_tools.append(tool)
            continue
        try:
            capabilities.append(DeviceCapability(value))
        except ValueError:
            continue
    return DeviceCapabilityReport(
        capabilities=capabilities,
        supported_tools=supported_tools,
    )


async def get_device_repository(
    db: AsyncSession = Depends(get_db),
) -> DeviceRepository:
    return SqlAlchemyDeviceRepository(db)
