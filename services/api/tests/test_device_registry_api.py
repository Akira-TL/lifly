from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.modules.auth.sessions import SessionRegistry, get_session_registry
from app.modules.devices.contracts import (
    DeviceCapabilityReport,
    DeviceTrustState,
)
from app.modules.devices.repository import (
    DeviceNotFound,
    DeviceRecord,
    get_device_repository,
)
from app.modules.devices.router import router as device_router


class _FakeDeviceRepository:
    def __init__(self) -> None:
        now = datetime(2026, 8, 15, tzinfo=timezone.utc)
        self.items = {
            "phone-1": DeviceRecord(
                device_id="phone-1",
                account_id="account-1",
                display_name="Phone",
                platform="android",
                public_key="phone-public-key",
                trust_state=DeviceTrustState.TRUSTED,
                capability_report=DeviceCapabilityReport(),
                is_default_compute_node=False,
                last_seen_at=now,
                revoked_at=None,
                key_version=1,
                protocol_version=1,
            ),
            "desktop-1": DeviceRecord(
                device_id="desktop-1",
                account_id="account-1",
                display_name="Desktop",
                platform="linux",
                public_key="desktop-public-key",
                trust_state=DeviceTrustState.TRUSTED,
                capability_report=DeviceCapabilityReport(
                    capabilities=["local_ai", "local_mcp"],
                    supported_tools=["memo.create"],
                ),
                is_default_compute_node=False,
                last_seen_at=now,
                revoked_at=None,
                key_version=1,
                protocol_version=1,
            ),
        }

    async def register_trusted(self, **kwargs) -> DeviceRecord:
        item = DeviceRecord(
            device_id=kwargs["device_id"],
            account_id=kwargs["account_id"],
            display_name=kwargs["display_name"],
            platform=kwargs["platform"],
            public_key=kwargs["public_key"],
            trust_state=DeviceTrustState.TRUSTED,
            capability_report=kwargs["capability_report"],
            is_default_compute_node=kwargs["make_default_compute_node"],
            last_seen_at=datetime.now(timezone.utc),
            revoked_at=None,
            key_version=1,
            protocol_version=1,
        )
        if item.is_default_compute_node:
            self.items = {
                key: replace(value, is_default_compute_node=False)
                for key, value in self.items.items()
            }
        self.items[item.device_id] = item
        return item

    async def list_for_account(self, account_id: str) -> list[DeviceRecord]:
        return [item for item in self.items.values() if item.account_id == account_id]

    async def get_for_account(self, account_id: str, device_id: str) -> DeviceRecord:
        item = self.items.get(device_id)
        if item is None or item.account_id != account_id:
            raise DeviceNotFound(device_id)
        return item

    async def rename(self, *, account_id: str, device_id: str, display_name: str) -> DeviceRecord:
        item = await self.get_for_account(account_id, device_id)
        item = replace(item, display_name=display_name)
        self.items[device_id] = item
        return item

    async def heartbeat(
        self,
        *,
        account_id: str,
        device_id: str,
        capability_report: DeviceCapabilityReport,
    ) -> DeviceRecord:
        item = await self.get_for_account(account_id, device_id)
        item = replace(
            item,
            capability_report=capability_report,
            last_seen_at=datetime.now(timezone.utc),
        )
        self.items[device_id] = item
        return item

    async def set_default_compute_node(self, *, account_id: str, device_id: str) -> DeviceRecord:
        selected = await self.get_for_account(account_id, device_id)
        self.items = {
            key: replace(value, is_default_compute_node=False)
            for key, value in self.items.items()
        }
        selected = replace(selected, is_default_compute_node=True)
        self.items[device_id] = selected
        return selected

    async def revoke(self, *, account_id: str, device_id: str) -> DeviceRecord:
        item = await self.get_for_account(account_id, device_id)
        item = replace(
            item,
            trust_state=DeviceTrustState.REVOKED,
            is_default_compute_node=False,
            revoked_at=datetime.now(timezone.utc),
        )
        self.items[device_id] = item
        return item


def _client() -> tuple[TestClient, _FakeDeviceRepository, SessionRegistry, str, str]:
    app = FastAPI()
    app.include_router(device_router, prefix="/api/v1/devices")
    devices = _FakeDeviceRepository()
    sessions = SessionRegistry()
    phone_session = sessions.issue(account_id="account-1", device_id="phone-1")
    desktop_session = sessions.issue(account_id="account-1", device_id="desktop-1")
    app.dependency_overrides[get_device_repository] = lambda: devices
    app.dependency_overrides[get_session_registry] = lambda: sessions
    return (
        TestClient(app),
        devices,
        sessions,
        phone_session.access_token,
        desktop_session.access_token,
    )


def test_list_rename_and_select_default_compute_node() -> None:
    client, _, _, phone_access, _ = _client()
    headers = {"Authorization": f"Bearer {phone_access}"}

    listed = client.get("/api/v1/devices", headers=headers)
    assert listed.status_code == 200, listed.text
    assert {item["device_id"] for item in listed.json()["devices"]} == {
        "phone-1",
        "desktop-1",
    }

    renamed = client.put(
        "/api/v1/devices/desktop-1",
        headers=headers,
        json={"display_name": "Workstation"},
    )
    assert renamed.status_code == 200, renamed.text
    assert renamed.json()["display_name"] == "Workstation"

    selected = client.put(
        "/api/v1/devices/desktop-1/default-compute-node",
        headers=headers,
    )
    assert selected.status_code == 200, selected.text
    assert selected.json()["is_default_compute_node"] is True

    listed_again = client.get("/api/v1/devices", headers=headers).json()["devices"]
    defaults = [item for item in listed_again if item["is_default_compute_node"]]
    assert [item["device_id"] for item in defaults] == ["desktop-1"]


def test_heartbeat_is_self_scoped_and_reports_capabilities() -> None:
    client, _, _, phone_access, desktop_access = _client()

    forbidden = client.post(
        "/api/v1/devices/desktop-1/heartbeat",
        headers={"Authorization": f"Bearer {phone_access}"},
        json={
            "capability_report": {
                "protocol_version": 1,
                "capabilities": ["local_ai"],
                "supported_tools": [],
            }
        },
    )
    assert forbidden.status_code == 403

    heartbeat = client.post(
        "/api/v1/devices/desktop-1/heartbeat",
        headers={"Authorization": f"Bearer {desktop_access}"},
        json={
            "capability_report": {
                "protocol_version": 1,
                "capabilities": ["local_ai", "background_executor"],
                "supported_tools": ["task.complete"],
            }
        },
    )
    assert heartbeat.status_code == 200, heartbeat.text
    report = heartbeat.json()["capability_report"]
    assert report["capabilities"] == ["local_ai", "background_executor"]
    assert report["supported_tools"] == ["task.complete"]
    assert heartbeat.json()["last_seen_at"] is not None


def test_revoke_device_revokes_only_that_devices_sessions() -> None:
    client, _, _, phone_access, desktop_access = _client()

    revoked = client.post(
        "/api/v1/devices/desktop-1/revoke",
        headers={"Authorization": f"Bearer {phone_access}"},
    )
    assert revoked.status_code == 200, revoked.text
    assert revoked.json()["device"]["trust_state"] == "revoked"
    assert revoked.json()["revoked_sessions"] == 1

    desktop_denied = client.get(
        "/api/v1/devices",
        headers={"Authorization": f"Bearer {desktop_access}"},
    )
    assert desktop_denied.status_code == 401

    phone_still_active = client.get(
        "/api/v1/devices",
        headers={"Authorization": f"Bearer {phone_access}"},
    )
    assert phone_still_active.status_code == 200
