from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import pytest
from jose import jwt

from app.core.config import settings
from app.core.security import AuthenticatedSubject
from app.db.models import EncryptedEntity
from app.modules.crypto.contracts import EncryptedEntityEnvelope
from app.modules.sync.encrypted_service import apply_encrypted_sync_push
from app.modules.sync.schemas import EncryptedSyncPushRequest
from app.modules.sync.service import issue_powersync_credentials


class FakeEncryptedSession:
    def __init__(self) -> None:
        self.entities: dict[tuple[str, str], EncryptedEntity] = {}
        self.flush_count = 0

    def add(self, item: Any) -> None:
        if not isinstance(item, EncryptedEntity):
            raise TypeError(f"Unsupported fake session item: {type(item)!r}")
        self.entities[(item.id, item.user_id)] = item

    async def flush(self) -> None:
        self.flush_count += 1


async def fake_find_encrypted_entity(
    db: FakeEncryptedSession,
    *,
    entity_id: str,
    user_id: str,
) -> EncryptedEntity | None:
    return db.entities.get((entity_id, user_id))


@pytest.fixture(autouse=True)
def patch_find_entity(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.modules.sync import encrypted_service

    monkeypatch.setattr(
        encrypted_service,
        "_find_encrypted_entity",
        fake_find_encrypted_entity,
    )


def _envelope(
    *,
    revision: int = 1,
    lifecycle_status: str = "active",
    user_id: str = "account-1",
    ciphertext: str = "Y2lwaGVydGV4dC1vbmx5",
) -> EncryptedEntityEnvelope:
    return EncryptedEntityEnvelope.model_validate(
        {
            "id": "entity-1",
            "user_id": user_id,
            "entity_type": "memo",
            "revision": revision,
            "lifecycle_status": lifecycle_status,
            "updated_at": datetime(2026, 8, 15, 10, tzinfo=timezone.utc),
            "key_version": 1,
            "encryption_version": 1,
            "nonce": "bm9uY2UtMTIz",
            "ciphertext": ciphertext,
        }
    )


@pytest.mark.anyio
async def test_encrypted_sync_persists_only_opaque_envelope_fields() -> None:
    session = FakeEncryptedSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")
    request = EncryptedSyncPushRequest(client_id="device-1", changes=[_envelope()])

    result = await apply_encrypted_sync_push(session, subject, request)  # type: ignore[arg-type]

    stored = session.entities[("entity-1", "account-1")]
    assert result.applied == 1
    assert result.skipped == 0
    assert stored.entity_type == "memo"
    assert stored.revision == 1
    assert stored.lifecycle_status == "active"
    assert stored.nonce == "bm9uY2UtMTIz"
    assert stored.ciphertext == "Y2lwaGVydGV4dC1vbmx5"
    assert not hasattr(stored, "title")
    assert not hasattr(stored, "content_markdown")
    assert not hasattr(stored, "amount")
    assert not hasattr(stored, "merchant")


@pytest.mark.anyio
async def test_encrypted_sync_rejects_cross_account_envelope() -> None:
    session = FakeEncryptedSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")
    request = EncryptedSyncPushRequest(
        client_id="device-1",
        changes=[_envelope(user_id="account-2")],
    )

    result = await apply_encrypted_sync_push(session, subject, request)  # type: ignore[arg-type]

    assert result.applied == 0
    assert result.skipped == 1
    assert result.results[0].reason == "tenant_mismatch"
    assert session.entities == {}


@pytest.mark.anyio
async def test_encrypted_sync_rejects_stale_revision_and_keeps_ciphertext() -> None:
    session = FakeEncryptedSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")
    first = EncryptedSyncPushRequest(client_id="device-1", changes=[_envelope(revision=2)])
    stale = EncryptedSyncPushRequest(
        client_id="device-1",
        changes=[_envelope(revision=1, ciphertext="c3RhbGUtY2lwaGVydGV4dA")],
    )

    await apply_encrypted_sync_push(session, subject, first)  # type: ignore[arg-type]
    result = await apply_encrypted_sync_push(session, subject, stale)  # type: ignore[arg-type]

    stored = session.entities[("entity-1", "account-1")]
    assert result.applied == 0
    assert result.skipped == 1
    assert result.results[0].reason == "stale_revision"
    assert stored.revision == 2
    assert stored.ciphertext == "Y2lwaGVydGV4dC1vbmx5"


@pytest.mark.anyio
async def test_encrypted_sync_applies_tombstone_as_opaque_revision() -> None:
    session = FakeEncryptedSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")
    await apply_encrypted_sync_push(  # type: ignore[arg-type]
        session,
        subject,
        EncryptedSyncPushRequest(client_id="device-1", changes=[_envelope(revision=1)]),
    )

    result = await apply_encrypted_sync_push(  # type: ignore[arg-type]
        session,
        subject,
        EncryptedSyncPushRequest(
            client_id="device-1",
            changes=[_envelope(revision=2, lifecycle_status="tombstone")],
        ),
    )

    stored = session.entities[("entity-1", "account-1")]
    assert result.applied == 1
    assert stored.revision == 2
    assert stored.lifecycle_status == "tombstone"


def test_powersync_credentials_are_bound_to_account_and_device() -> None:
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")

    credentials = issue_powersync_credentials(subject)
    payload = jwt.decode(
        credentials.token,
        settings.jwt_secret,
        algorithms=[settings.jwt_algorithm],
        audience=settings.powersync_url,
    )

    assert credentials.user_id == "account-1"
    assert credentials.device_id == "device-1"
    assert credentials.mode == "authenticated"
    assert payload["sub"] == "account-1"
    assert payload["account_id"] == "account-1"
    assert payload["user_id"] == "account-1"
    assert payload["device_id"] == "device-1"
    assert payload["type"] == "powersync"
    assert payload["aud"] == settings.powersync_url
    assert "iat" in payload


def test_powersync_credentials_require_device_identity() -> None:
    with pytest.raises(ValueError, match="device identity"):
        issue_powersync_credentials(AuthenticatedSubject(account_id="account-1"))
