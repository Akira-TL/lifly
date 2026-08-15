from __future__ import annotations

from typing import Any

import pytest
from mcp.server.auth.provider import AccessToken

from app.modules.auth.sessions import SessionRegistry
from app.modules.mcp import cloud_server


@pytest.mark.anyio
async def test_mcp_verifier_accepts_active_session_and_rejects_revoked(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    sessions = SessionRegistry()
    issued = sessions.issue(account_id="account-1", device_id="device-1")
    monkeypatch.setattr(cloud_server, "get_session_registry", lambda: sessions)
    verifier = cloud_server.LiflyMcpTokenVerifier()

    access = await verifier.verify_token(issued.access_token)
    assert access is not None
    assert access.subject == "account-1"
    assert access.claims == {
        "account_id": "account-1",
        "device_id": "device-1",
    }

    assert sessions.revoke_access(issued.access_token) is True
    assert await verifier.verify_token(issued.access_token) is None


@pytest.mark.anyio
async def test_mcp_internal_call_forwards_same_authenticated_bearer(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    seen: dict[str, Any] = {}
    access = AccessToken(
        token="session-token",
        client_id="device-1",
        scopes=["lifly:mcp"],
        subject="account-1",
    )
    monkeypatch.setattr(cloud_server, "get_access_token", lambda: access)

    class Response:
        def raise_for_status(self) -> None:
            pass

        def json(self) -> dict[str, object]:
            return {"ok": True}

    class Client:
        async def __aenter__(self) -> "Client":
            return self

        async def __aexit__(self, *_args: object) -> None:
            pass

        async def post(self, url: str, **kwargs: Any) -> Response:
            seen["url"] = url
            seen.update(kwargs)
            return Response()

    monkeypatch.setattr(cloud_server.httpx, "AsyncClient", lambda **_kwargs: Client())

    assert await cloud_server._call_internal("/api/v1/mcp/task/list", {}) == {"ok": True}
    assert seen["headers"] == {"Authorization": "Bearer session-token"}
    assert seen["json"] == {}


@pytest.mark.anyio
async def test_mcp_internal_call_fails_closed_without_auth_context(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(cloud_server, "get_access_token", lambda: None)
    with pytest.raises(RuntimeError, match="Authenticated MCP access token"):
        await cloud_server._call_internal("/api/v1/mcp/task/list", {})
