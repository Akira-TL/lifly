from __future__ import annotations

import inspect
from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.db.models import Asset
from app.modules.assets import router as asset_router
from app.modules.assets import service as asset_service
from app.modules.assets.service import (
    ASSET_CONTRACT_VERSION,
    ASSET_CREATE_UPLOAD_AUDIT_ACTION,
    ASSET_REGISTER_EXTERNAL_AUDIT_ACTION,
    ASSET_STATUS_ACTIVE,
    ASSET_STATUS_AI_TRASHED,
    ASSET_STATUS_DELETED,
    ASSET_SYNC_PENDING,
    ASSET_SYNC_SYNCED,
    ASSET_TRASH_AUDIT_ACTION,
    ASSET_UPDATE_METADATA_AUDIT_ACTION,
    ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
    build_create_upload_url_payload,
    build_register_external_url_payload,
)
from app.modules.mcp import router as mcp_router
from app.schemas.common import AssetCreateUploadUrl, AssetRegisterExternalUrl


NOW = datetime(2026, 7, 4, 8, 0, tzinfo=timezone.utc)


def _asset(**overrides: object) -> Asset:
    data = {
        "id": "asset_1",
        "user_id": "local-dev",
        "kind": "internal",
        "asset_type": "file",
        "filename": "demo.txt",
        "mime_type": "text/plain",
        "size_bytes": 12,
        "sha256": None,
        "storage_provider": "minio",
        "storage_key": "attachments/local-dev/asset_1/demo.txt",
        "external_url": None,
        "external_provider": None,
        "visibility": "private",
        "sync_status": ASSET_SYNC_PENDING,
        "status": ASSET_STATUS_ACTIVE,
        "created_at": NOW,
        "updated_at": NOW,
    }
    data.update(overrides)
    return Asset(**data)


def test_asset_upload_input_rejects_path_like_filename() -> None:
    with pytest.raises(ValidationError):
        AssetCreateUploadUrl.model_validate({"filename": "../secret.txt"})

    with pytest.raises(ValidationError):
        AssetCreateUploadUrl.model_validate({"filename": "folder/demo.txt"})

    with pytest.raises(ValidationError):
        AssetCreateUploadUrl.model_validate({"filename": "demo.txt", "size_bytes": -1})

    payload = AssetCreateUploadUrl.model_validate({
        "filename": " demo.txt ",
        "mime_type": " text/plain ",
        "size_bytes": 0,
    })
    assert payload.filename == "demo.txt"
    assert payload.mime_type == "text/plain"


def test_external_asset_input_rejects_non_http_url() -> None:
    with pytest.raises(ValidationError):
        AssetRegisterExternalUrl.model_validate({"external_url": "file:///tmp/demo.txt"})

    payload = AssetRegisterExternalUrl.model_validate({
        "external_url": " https://example.com/demo ",
        "external_provider": " notion ",
        "title": " Demo ",
    })
    assert payload.external_url == "https://example.com/demo"
    assert payload.external_provider == "notion"
    assert payload.title == "Demo"


def test_internal_upload_payload_keeps_legacy_fields_and_exposes_intent_boundaries() -> None:
    asset = _asset()
    payload = build_create_upload_url_payload(asset, "http://localhost:9000/upload/demo.txt")

    assert payload["contract_version"] == ASSET_CONTRACT_VERSION
    assert payload["asset_id"] == asset.id
    assert payload["storage_key"] == asset.storage_key
    assert payload["upload_url"].startswith("http://")
    assert payload["asset"]["id"] == asset.id
    assert payload["asset"]["title"] == "demo.txt"

    intent = payload["upload_intent"]
    assert intent["intent_type"] == "internal_upload"
    assert intent["method"] == "PUT"
    assert intent["requires_upload_complete"] is True
    assert intent["sync_status"] == ASSET_SYNC_PENDING
    assert intent["sync_boundary"]["internal_upload_initial"] == ASSET_SYNC_PENDING
    assert intent["sync_boundary"]["internal_upload_complete"] == ASSET_SYNC_SYNCED
    assert intent["status_boundary"]["ai_undo_trash"] == ASSET_STATUS_AI_TRASHED
    assert intent["trash_boundary"]["api_delete_status"] == ASSET_STATUS_DELETED

    metadata = payload["metadata"]
    assert metadata["contract_version"] == ASSET_CONTRACT_VERSION
    assert metadata["asset_id"] == asset.id
    assert metadata["status"] == ASSET_STATUS_ACTIVE
    assert metadata["sync_status"] == ASSET_SYNC_PENDING


def test_external_registration_payload_exposes_reference_boundaries() -> None:
    asset = _asset(
        kind="external",
        asset_type="link",
        filename="Lifly",
        mime_type=None,
        size_bytes=None,
        storage_provider=None,
        storage_key=None,
        external_url="https://example.com/lifly",
        external_provider="web",
        sync_status=ASSET_SYNC_SYNCED,
    )
    payload = build_register_external_url_payload(asset)

    assert payload["contract_version"] == ASSET_CONTRACT_VERSION
    assert payload["asset_id"] == asset.id
    assert payload["external_url"] == "https://example.com/lifly"
    assert payload["asset"]["title"] == "Lifly"
    assert payload["metadata"]["sync_status"] == ASSET_SYNC_SYNCED
    assert payload["external_registration"]["intent_type"] == "external_reference"
    assert payload["external_registration"]["requires_upload_complete"] is False
    assert payload["external_registration"]["sync_boundary"]["external_reference"] == ASSET_SYNC_SYNCED


def test_asset_rest_handlers_write_unified_audit_actions() -> None:
    service_source = inspect.getsource(asset_service)

    assert "ASSET_CREATE_UPLOAD_AUDIT_ACTION" in service_source
    assert "ASSET_REGISTER_EXTERNAL_AUDIT_ACTION" in service_source
    assert ASSET_CREATE_UPLOAD_AUDIT_ACTION in service_source
    assert ASSET_REGISTER_EXTERNAL_AUDIT_ACTION in service_source
    assert "build_create_upload_url_payload" in inspect.getsource(asset_router.create_upload_url)
    assert "build_register_external_url_payload" in inspect.getsource(asset_router.register_external_url)

    for handler, action_name, action_value in [
        (asset_router.upload_complete, "ASSET_UPLOAD_COMPLETE_AUDIT_ACTION", ASSET_UPLOAD_COMPLETE_AUDIT_ACTION),
        (asset_router.update_asset, "ASSET_UPDATE_METADATA_AUDIT_ACTION", ASSET_UPDATE_METADATA_AUDIT_ACTION),
        (asset_router.delete_asset, "ASSET_TRASH_AUDIT_ACTION", ASSET_TRASH_AUDIT_ACTION),
    ]:
        source = inspect.getsource(handler)
        assert "write_asset_audit" in source
        assert action_name in source
        assert action_value
        assert "before=before" in source
        assert "after=after" in source


def test_mcp_asset_handlers_return_hardened_payload_with_undo_token() -> None:
    upload_source = inspect.getsource(mcp_router.mcp_asset_create_upload_url)
    external_source = inspect.getsource(mcp_router.mcp_asset_register_external_url)

    assert "build_create_upload_url_payload(asset, upload_url)" in upload_source
    assert '"undo_token": undo_token' in upload_source
    assert "build_register_external_url_payload(asset)" in external_source
    assert '"undo_token": undo_token' in external_source
