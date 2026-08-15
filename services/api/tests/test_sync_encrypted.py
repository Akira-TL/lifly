from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import pytest
from jose import jwt

from app.core.config import settings
from app.core.security import AuthenticatedSubject
from app.db.models import AccountKeyEnvelope, EncryptedEntity
from app.modules.crypto.contracts import EncryptedEntityEnvelope, PasswordKeyEnvelope
from app.modules.sync.encrypted_service import (
    apply_encrypted_sync_push,
    get_password_key_envelope,
    store_password_key_envelope,
)
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


class FakeKeyEnvelopeSession:
    def __init__(self) -> None:
        self.envelopes: dict[tuple[str, int], AccountKeyEnvelope] = {}
        self.flush_count = 0

    def add(self, item: Any) -> None:
        if not isinstance(item, AccountKeyEnvelope):
            raise TypeError(f"Unsupported fake session item: {type(item)!r}")
        self.envelopes[(item.account_id, item.key_version)] = item

    async def flush(self) -> None:
        self.flush_count += 1


async def fake_find_password_key_envelope(
    db: FakeKeyEnvelopeSession,
    *,
    account_id: str,
    key_version: int | None,
) -> AccountKeyEnvelope | None:
    if key_version is not None:
        return db.envelopes.get((account_id, key_version))
    matches = [
        item
        for (owner, _), item in db.envelopes.items()
        if owner == account_id
    ]
    if not matches:
        return None
    return max(matches, key=lambda item: item.key_version)


def _password_envelope(
    *,
    account_id: str = "account-1",
    key_version: int = 1,
    ciphertext: str = "d3JhcHBlZC1hZGs=",
) -> PasswordKeyEnvelope:
    return PasswordKeyEnvelope.model_validate(
        {
            "account_id": account_id,
            "key_version": key_version,
            "encryption_version": 1,
            "nonce": "cGFzc3dvcmQtbm9uY2U=",
            "ciphertext": ciphertext,
        }
    )


@pytest.mark.anyio
async def test_password_key_envelope_is_stored_as_opaque_account_ciphertext(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.modules.sync import encrypted_service

    monkeypatch.setattr(
        encrypted_service,
        "_find_password_key_envelope",
        fake_find_password_key_envelope,
    )
    session = FakeKeyEnvelopeSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")

    stored = await store_password_key_envelope(  # type: ignore[arg-type]
        session,
        subject,
        _password_envelope(),
    )

    assert stored.account_id == "account-1"
    assert stored.key_version == 1
    assert stored.ciphertext == "d3JhcHBlZC1hZGs="
    assert not hasattr(session.envelopes[("account-1", 1)], "password")
    assert not hasattr(session.envelopes[("account-1", 1)], "adk")


@pytest.mark.anyio
async def test_password_key_envelope_rejects_cross_account_write(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.modules.sync import encrypted_service

    monkeypatch.setattr(
        encrypted_service,
        "_find_password_key_envelope",
        fake_find_password_key_envelope,
    )
    session = FakeKeyEnvelopeSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")

    with pytest.raises(PermissionError, match="account"):
        await store_password_key_envelope(  # type: ignore[arg-type]
            session,
            subject,
            _password_envelope(account_id="account-2"),
        )

    assert session.envelopes == {}


@pytest.mark.anyio
async def test_password_key_envelope_reads_latest_or_requested_version(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.modules.sync import encrypted_service

    monkeypatch.setattr(
        encrypted_service,
        "_find_password_key_envelope",
        fake_find_password_key_envelope,
    )
    session = FakeKeyEnvelopeSession()
    subject = AuthenticatedSubject(account_id="account-1", device_id="device-1")
    await store_password_key_envelope(  # type: ignore[arg-type]
        session,
        subject,
        _password_envelope(key_version=1),
    )
    await store_password_key_envelope(  # type: ignore[arg-type]
        session,
        subject,
        _password_envelope(key_version=2, ciphertext="djItd3JhcHBlZC1hZGs="),
    )

    latest = await get_password_key_envelope(  # type: ignore[arg-type]
        session,
        subject,
    )
    version1 = await get_password_key_envelope(  # type: ignore[arg-type]
        session,
        subject,
        key_version=1,
    )

    assert latest is not None
    assert latest.key_version == 2
    assert version1 is not None
    assert version1.key_version == 1
