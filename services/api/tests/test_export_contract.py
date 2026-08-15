from __future__ import annotations

import inspect
import json
from datetime import datetime, timezone

import pytest

from app.db.models import AccountKeyEnvelope, Asset, EncryptedEntity
from app.modules.imexport import exporter
from app.modules.imexport import router as imexport_router


NOW = datetime(2026, 8, 15, 10, tzinfo=timezone.utc)


class _ScalarRows:
    def __init__(self, rows: list[object]) -> None:
        self._rows = rows

    def all(self) -> list[object]:
        return self._rows


class _Result:
    def __init__(self, rows: list[object]) -> None:
        self._rows = rows

    def scalars(self) -> _ScalarRows:
        return _ScalarRows(self._rows)


class _FakeSession:
    def __init__(self, *batches: list[object]) -> None:
        self._batches = list(batches)

    async def execute(self, statement: object) -> _Result:
        del statement
        return _Result(self._batches.pop(0))


def _encrypted_entity() -> EncryptedEntity:
    return EncryptedEntity(
        id="entity-1",
        user_id="account-1",
        entity_type="memo",
        revision=3,
        lifecycle_status="active",
        key_version=2,
        encryption_version=1,
        schema_version=1,
        nonce="bm9uY2U=",
        ciphertext="Y2lwaGVydGV4dA==",
        created_at=NOW,
        updated_at=NOW,
    )


def _key_envelope() -> AccountKeyEnvelope:
    return AccountKeyEnvelope(
        id="key-envelope-1",
        account_id="account-1",
        envelope_type="password",
        key_version=2,
        encryption_version=1,
        schema_version=1,
        nonce="a2V5LW5vbmNl",
        ciphertext="d3JhcHBlZC1hZGs=",
        created_at=NOW,
        updated_at=NOW,
    )


def _asset() -> Asset:
    return Asset(
        id="asset-1",
        user_id="account-1",
        kind="internal",
        asset_type="file",
        filename=None,
        mime_type="application/octet-stream",
        size_bytes=321,
        sha256="a" * 64,
        storage_provider="minio",
        storage_key="attachments/account-1/asset-1/payload.e2ee",
        external_url=None,
        external_provider=None,
        visibility="private",
        sync_status="synced",
        status="active",
        created_at=NOW,
        updated_at=NOW,
    )


def test_plaintext_export_boundary_is_client_only_and_warns_user() -> None:
    boundary = exporter.plaintext_export_boundary().metadata()

    assert boundary["contract_version"] == "export.e2ee.v1"
    assert boundary["mode"] == "plaintext"
    assert boundary["execution_location"] == "trusted_client"
    assert boundary["contains_decrypted_user_data"] is True
    assert boundary["available_from_cloud"] is False
    assert "明文" in boundary["privacy_warning"]
    assert "受信设备" in boundary["privacy_warning"]


@pytest.mark.anyio
async def test_encrypted_backup_contains_only_opaque_envelopes_and_object_manifest() -> None:
    db = _FakeSession([_encrypted_entity()], [_key_envelope()], [_asset()])

    result = await exporter.build_encrypted_backup_result(
        db,
        user_id="account-1",
        include_asset_ciphertext=False,
    )
    payload = json.loads(result.content)

    assert result.mode == "encrypted_backup"
    assert result.filename == "lifly-encrypted-backup.json"
    assert result.counts == {
        "encrypted_entities": 1,
        "account_key_envelopes": 1,
        "encrypted_asset_objects": 1,
    }
    assert payload["encrypted_entities"][0]["ciphertext"] == "Y2lwaGVydGV4dA=="
    assert payload["account_key_envelopes"][0]["ciphertext"] == "d3JhcHBlZC1hZGs="
    assert payload["encrypted_asset_objects"][0]["storage_key"].endswith("payload.e2ee")
    serialized = result.content.decode()
    assert "filename" not in serialized
    assert "mime_type" not in serialized
    assert "external_url" not in serialized
    assert "private memo title" not in serialized


@pytest.mark.anyio
async def test_encrypted_backup_can_embed_attachment_ciphertext(monkeypatch: pytest.MonkeyPatch) -> None:
    db = _FakeSession([_encrypted_entity()], [_key_envelope()], [_asset()])
    monkeypatch.setattr(
        exporter,
        "_read_asset_ciphertext",
        lambda storage_key: b"LFLYAS01\x00\x01ciphertext",
    )

    result = await exporter.build_encrypted_backup_result(
        db,
        user_id="account-1",
        include_asset_ciphertext=True,
    )
    payload = json.loads(result.content)

    embedded = payload["encrypted_asset_objects"][0]["ciphertext_base64"]
    assert embedded
    assert "LFLYAS01" not in embedded


def test_export_routes_never_call_server_plaintext_exporter() -> None:
    metadata_source = inspect.getsource(imexport_router.export_data)
    stream_source = inspect.getsource(imexport_router.export_stream)

    assert "plaintext_export_boundary" in metadata_source
    assert "trusted client" not in metadata_source.lower()
    assert "build_encrypted_backup_result" in metadata_source
    assert "build_encrypted_backup_result" in stream_source
    assert "Plaintext export must be generated on the trusted client device" in stream_source
    assert "build_export_result" not in metadata_source
    assert "build_export_result" not in stream_source
    assert "get_active_subject" in inspect.getsource(imexport_router)


def test_import_export_cloud_audit_is_operational_only() -> None:
    source = inspect.getsource(imexport_router._write_audit)

    assert "before_snapshot=None" in source
    assert "after_snapshot=None" in source
    assert "source_text=None" in source
