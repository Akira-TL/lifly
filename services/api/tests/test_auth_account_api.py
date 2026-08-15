from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.modules.account.repository import AccountRecord, get_account_repository
from app.modules.account.router import router as account_router
from app.modules.auth.flows import AuthFlowStore, get_auth_flow_store
from app.modules.auth.pake import PakeServerStart, get_pake_server_adapter
from app.modules.auth.router import router as auth_router
from app.modules.auth.sessions import SessionRegistry, get_session_registry
from app.modules.devices.contracts import DeviceCapabilityReport, DeviceTrustState
from app.modules.devices.repository import DeviceNotFound, DeviceRecord, get_device_repository


@dataclass
class _FakeAccountRepository:
    by_phone: dict[str, AccountRecord]
    credentials: dict[str, str]

    def __init__(self) -> None:
        self.by_phone = {}
        self.credentials = {}

    async def find_by_phone(self, phone_e164: str) -> AccountRecord | None:
        return self.by_phone.get(phone_e164)

    async def find_by_id(self, account_id: str) -> AccountRecord | None:
        return next(
            (item for item in self.by_phone.values() if item.account_id == account_id),
            None,
        )

    async def get_credential_record(self, account_id: str) -> str | None:
        return self.credentials.get(account_id)

    async def create_account(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        credential_record: str,
    ) -> AccountRecord:
        if phone_e164 in self.by_phone:
            raise ValueError("duplicate account")
        account = AccountRecord(
            account_id="account-1",
            phone_e164=phone_e164,
            display_name=display_name,
            account_status="active",
            plan="demo",
        )
        self.by_phone[phone_e164] = account
        self.credentials[account.account_id] = credential_record
        return account


class _FakeDeviceRepository:
    def __init__(self) -> None:
        self.items: dict[str, DeviceRecord] = {}

    async def register_trusted(self, **kwargs) -> DeviceRecord:
        now = datetime.now(timezone.utc)
        item = DeviceRecord(
            device_id=kwargs["device_id"],
            account_id=kwargs["account_id"],
            display_name=kwargs["display_name"],
            platform=kwargs["platform"],
            public_key=kwargs["public_key"],
            trust_state=DeviceTrustState.TRUSTED,
            capability_report=kwargs["capability_report"],
            is_default_compute_node=kwargs["make_default_compute_node"],
            last_seen_at=now,
            revoked_at=None,
            key_version=1,
            protocol_version=1,
        )
        if item.is_default_compute_node:
            self.items = {
                key: DeviceRecord(
                    device_id=value.device_id,
                    account_id=value.account_id,
                    display_name=value.display_name,
                    platform=value.platform,
                    public_key=value.public_key,
                    trust_state=value.trust_state,
                    capability_report=value.capability_report,
                    is_default_compute_node=False,
                    last_seen_at=value.last_seen_at,
                    revoked_at=value.revoked_at,
                    key_version=value.key_version,
                    protocol_version=value.protocol_version,
                )
                for key, value in self.items.items()
            }
        self.items[item.device_id] = item
        return item

    async def get_for_account(self, account_id: str, device_id: str) -> DeviceRecord:
        item = self.items.get(device_id)
        if item is None or item.account_id != account_id:
            raise DeviceNotFound(device_id)
        return item


class _FakePakeAdapter:
    protocol = "opaque-rfc9807"
    protocol_version = 1

    async def registration_start(
        self, *, identifier: str, client_request: str
    ) -> PakeServerStart:
        assert identifier.startswith("+")
        assert client_request == "registration-request"
        return PakeServerStart(
            server_response="registration-response",
            server_state="registration-state",
        )

    async def registration_finish(
        self, *, identifier: str, server_state: str, client_upload: str
    ) -> str:
        assert server_state == "registration-state"
        assert client_upload == "registration-upload"
        return "opaque-credential-record"

    async def login_start(
        self,
        *,
        identifier: str,
        credential_record: str | None,
        client_request: str,
    ) -> PakeServerStart:
        assert client_request == "login-request"
        # Unknown identities still receive a syntactically identical response.
        return PakeServerStart(
            server_response="login-response",
            server_state="known" if credential_record else "unknown",
        )

    async def login_finish(
        self, *, identifier: str, server_state: str, client_finish: str
    ) -> bool:
        return server_state == "known" and client_finish == "login-finish"


def _device_payload(device_id: str, *, compute: bool = False) -> dict[str, object]:
    return {
        "device_id": device_id,
        "display_name": "Demo Device",
        "platform": "android" if not compute else "linux",
        "public_key": f"public-key-{device_id}",
        "capability_report": {
            "protocol_version": 1,
            "capabilities": ["local_ai", "local_mcp"] if compute else [],
            "supported_tools": ["memo.create"] if compute else [],
        },
        "make_default_compute_node": compute,
    }


def _client() -> tuple[
    TestClient,
    _FakeAccountRepository,
    _FakeDeviceRepository,
    SessionRegistry,
]:
    app = FastAPI()
    app.include_router(auth_router, prefix="/api/v1/auth")
    app.include_router(account_router, prefix="/api/v1/account")

    accounts = _FakeAccountRepository()
    devices = _FakeDeviceRepository()
    sessions = SessionRegistry()
    flows = AuthFlowStore(ttl_seconds=60)
    app.dependency_overrides[get_account_repository] = lambda: accounts
    app.dependency_overrides[get_device_repository] = lambda: devices
    app.dependency_overrides[get_pake_server_adapter] = lambda: _FakePakeAdapter()
    app.dependency_overrides[get_auth_flow_store] = lambda: flows
    app.dependency_overrides[get_session_registry] = lambda: sessions
    return TestClient(app), accounts, devices, sessions


def _register(client: TestClient, *, device_id: str = "phone-1") -> dict[str, object]:
    start = client.post(
        "/api/v1/auth/register/start",
        json={
            "phone": "+8613800138000",
            "client_request": "registration-request",
        },
    ).json()
    response = client.post(
        "/api/v1/auth/register/finish",
        json={
            "flow_id": start["flow_id"],
            "client_upload": "registration-upload",
            "device": _device_payload(device_id),
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


def test_register_normalizes_phone_and_auto_enrolls_trusted_device() -> None:
    client, accounts, devices, _ = _client()

    start = client.post(
        "/api/v1/auth/register/start",
        json={
            "phone": "138 0013 8000",
            "region": "CN",
            "display_name": "Demo User",
            "client_request": "registration-request",
        },
    )
    assert start.status_code == 200, start.text
    start_body = start.json()
    assert start_body["phone_e164"] == "+8613800138000"
    assert start_body["server_response"] == "registration-response"
    assert "password" not in start.request.content.decode().lower()

    finish = client.post(
        "/api/v1/auth/register/finish",
        json={
            "flow_id": start_body["flow_id"],
            "client_upload": "registration-upload",
            "device": _device_payload("phone-1"),
        },
    )
    assert finish.status_code == 200, finish.text
    body = finish.json()
    assert body["account"]["phone_e164"] == "+8613800138000"
    assert body["account"]["account_id"] == "account-1"
    assert body["device"]["device_id"] == "phone-1"
    assert body["device"]["trust_state"] == "trusted"
    assert body["access_token"]
    assert body["refresh_token"].startswith("lifly_refresh_")
    assert accounts.credentials["account-1"] == "opaque-credential-record"
    assert devices.items["phone-1"].trust_state is DeviceTrustState.TRUSTED


def test_login_masks_unknown_account_until_finish_without_enrollment() -> None:
    client, _, devices, _ = _client()

    start = client.post(
        "/api/v1/auth/login/start",
        json={
            "phone": "+8613900000000",
            "client_request": "login-request",
        },
    )
    assert start.status_code == 200, start.text
    assert start.json()["server_response"] == "login-response"

    finish = client.post(
        "/api/v1/auth/login/finish",
        json={
            "flow_id": start.json()["flow_id"],
            "client_finish": "login-finish",
            "device": _device_payload("attacker-device"),
        },
    )
    assert finish.status_code == 401
    assert finish.json()["detail"] == "Invalid phone or password"
    assert devices.items == {}


def test_password_login_enrolls_new_device_and_can_make_it_default_compute_node() -> None:
    client, _, devices, _ = _client()
    _register(client)

    start = client.post(
        "/api/v1/auth/login/start",
        json={
            "phone": "+8613800138000",
            "client_request": "login-request",
        },
    )
    assert start.status_code == 200, start.text
    finish = client.post(
        "/api/v1/auth/login/finish",
        json={
            "flow_id": start.json()["flow_id"],
            "client_finish": "login-finish",
            "device": _device_payload("desktop-1", compute=True),
        },
    )
    assert finish.status_code == 200, finish.text
    body = finish.json()
    assert body["device"]["device_id"] == "desktop-1"
    assert body["device"]["trust_state"] == "trusted"
    assert body["device"]["is_default_compute_node"] is True
    assert body["device"]["capability_report"]["capabilities"] == [
        "local_ai",
        "local_mcp",
    ]
    assert devices.items["phone-1"].is_default_compute_node is False


def test_refresh_rotates_token_and_revoke_invalidates_account_profile() -> None:
    client, _, _, _ = _client()
    registered = _register(client)

    first_access = registered["access_token"]
    first_refresh = registered["refresh_token"]
    refreshed_response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first_refresh}
    )
    assert refreshed_response.status_code == 200, refreshed_response.text
    refreshed = refreshed_response.json()
    assert refreshed["refresh_token"] != first_refresh
    assert refreshed["device"]["device_id"] == "phone-1"
    assert refreshed["device"]["trust_state"] == "trusted"

    stale_refresh = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first_refresh}
    )
    assert stale_refresh.status_code == 401

    me = client.get(
        "/api/v1/account/me",
        headers={"Authorization": f"Bearer {refreshed['access_token']}"},
    )
    assert me.status_code == 200
    assert me.json()["account_id"] == "account-1"

    revoked = client.post(
        "/api/v1/auth/revoke",
        headers={"Authorization": f"Bearer {refreshed['access_token']}"},
    )
    assert revoked.status_code == 200
    assert revoked.json() == {"ok": True}

    denied = client.get(
        "/api/v1/account/me",
        headers={"Authorization": f"Bearer {refreshed['access_token']}"},
    )
    assert denied.status_code == 401

    # Access issued before refresh belongs to the same session and is revoked too.
    denied_old_access = client.get(
        "/api/v1/account/me",
        headers={"Authorization": f"Bearer {first_access}"},
    )
    assert denied_old_access.status_code == 401
