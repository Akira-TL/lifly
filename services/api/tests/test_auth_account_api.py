from __future__ import annotations

from dataclasses import dataclass

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.modules.account.repository import AccountRecord, get_account_repository
from app.modules.account.router import router as account_router
from app.modules.auth.flows import AuthFlowStore, get_auth_flow_store
from app.modules.auth.pake import PakeServerStart, get_pake_server_adapter
from app.modules.auth.router import router as auth_router
from app.modules.auth.sessions import SessionRegistry, get_session_registry


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


def _client() -> tuple[TestClient, _FakeAccountRepository, SessionRegistry]:
    app = FastAPI()
    app.include_router(auth_router, prefix="/api/v1/auth")
    app.include_router(account_router, prefix="/api/v1/account")

    accounts = _FakeAccountRepository()
    sessions = SessionRegistry()
    flows = AuthFlowStore(ttl_seconds=60)
    app.dependency_overrides[get_account_repository] = lambda: accounts
    app.dependency_overrides[get_pake_server_adapter] = lambda: _FakePakeAdapter()
    app.dependency_overrides[get_auth_flow_store] = lambda: flows
    app.dependency_overrides[get_session_registry] = lambda: sessions
    return TestClient(app), accounts, sessions


def test_register_normalizes_phone_without_transmitting_password() -> None:
    client, accounts, _ = _client()

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
        },
    )
    assert finish.status_code == 200, finish.text
    body = finish.json()
    assert body["account"]["phone_e164"] == "+8613800138000"
    assert body["account"]["account_id"] == "account-1"
    assert body["access_token"]
    assert body["refresh_token"].startswith("lifly_refresh_")
    assert accounts.credentials["account-1"] == "opaque-credential-record"


def test_login_masks_unknown_account_until_finish() -> None:
    client, _, _ = _client()

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
        json={"flow_id": start.json()["flow_id"], "client_finish": "login-finish"},
    )
    assert finish.status_code == 401
    assert finish.json()["detail"] == "Invalid phone or password"


def test_refresh_rotates_token_and_revoke_invalidates_account_profile() -> None:
    client, _, _ = _client()

    register_start = client.post(
        "/api/v1/auth/register/start",
        json={
            "phone": "+8613800138000",
            "client_request": "registration-request",
        },
    ).json()
    registered = client.post(
        "/api/v1/auth/register/finish",
        json={
            "flow_id": register_start["flow_id"],
            "client_upload": "registration-upload",
        },
    ).json()

    first_access = registered["access_token"]
    first_refresh = registered["refresh_token"]
    refreshed_response = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first_refresh}
    )
    assert refreshed_response.status_code == 200, refreshed_response.text
    refreshed = refreshed_response.json()
    assert refreshed["refresh_token"] != first_refresh

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
