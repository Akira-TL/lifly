from __future__ import annotations

from datetime import datetime, timezone

from app.core.security import decode_token
from app.modules.sync.service import issue_powersync_credentials


def test_issue_powersync_credentials_returns_development_token() -> None:
    before = datetime.now(timezone.utc)
    credentials = issue_powersync_credentials()
    after = datetime.now(timezone.utc)

    assert credentials.endpoint == "http://localhost:8204"
    assert credentials.user_id == "local-dev"
    assert credentials.mode == "development"
    assert credentials.token
    assert credentials.expires_at > before
    assert credentials.expires_at > after

    payload = decode_token(credentials.token)
    assert payload is not None
    assert payload["sub"] == "local-dev"
    assert payload["type"] == "access"
