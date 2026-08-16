from __future__ import annotations

from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient
from jose import jwt

from app.core.config import settings
from app.core.security import AuthenticatedSubject
from app.modules.auth.sessions import get_active_subject
from app.modules.sync.router import router as sync_router
from app.modules.sync.service import issue_powersync_credentials


def test_forwarded_public_host_returns_same_origin_powersync_endpoint() -> None:
    app = FastAPI()
    app.include_router(sync_router, prefix="/api/v1/sync")
    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1",
        device_id="device-1",
    )
    response = TestClient(app).get(
        "/api/v1/sync/credentials",
        headers={
            "X-Forwarded-Host": "lifly.babelbeast.com",
            "X-Forwarded-Proto": "https",
        },
    )

    assert response.status_code == 200, response.text
    data = response.json()["data"]
    endpoint = "https://lifly.babelbeast.com/powersync"
    assert data["endpoint"] == endpoint
    payload = jwt.decode(
        data["token"],
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        audience=endpoint,
    )
    assert payload["aud"] == endpoint


def test_public_powersync_endpoint_becomes_jwt_audience() -> None:
    endpoint = "https://lifly.babelbeast.com/powersync"
    credentials = issue_powersync_credentials(
        AuthenticatedSubject(account_id="account-1", device_id="device-1"),
        endpoint=endpoint,
    )

    assert credentials.endpoint == endpoint
    payload = jwt.decode(
        credentials.token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        audience=endpoint,
    )
    assert payload["aud"] == endpoint


def test_issue_powersync_credentials_returns_authenticated_device_token() -> None:
    before = datetime.now(timezone.utc)
    credentials = issue_powersync_credentials(
        AuthenticatedSubject(account_id="account-1", device_id="device-1")
    )
    after = datetime.now(timezone.utc)

    assert credentials.endpoint == "http://localhost:8204"
    assert credentials.user_id == "account-1"
    assert credentials.device_id == "device-1"
    assert credentials.mode == "authenticated"
    assert credentials.token
    assert credentials.expires_at > before
    assert credentials.expires_at > after

    payload = jwt.decode(
        credentials.token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        audience=settings.powersync_url,
    )
    assert payload["sub"] == "account-1"
    assert payload["account_id"] == "account-1"
    assert payload["device_id"] == "device-1"
    assert payload["type"] == "powersync"
    assert payload["aud"] == settings.powersync_url
    assert payload["iat"] <= payload["exp"]
