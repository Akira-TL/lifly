from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.storage import generate_upload_url, get_storage
from app.db.models import Asset, AuditLog
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    AssetResponse,
)

DEFAULT_LOCAL_USER_ID = "local-dev"

ASSET_CONTRACT_VERSION = "asset.v0.5.1"
ASSET_E2EE_CONTRACT_VERSION = "asset.e2ee.v1"
ENCRYPTED_ASSET_MAGIC = b"LFLYAS01"

ASSET_KIND_INTERNAL = "internal"
ASSET_KIND_EXTERNAL = "external"

ASSET_STATUS_ACTIVE = "active"
ASSET_STATUS_DELETED = "deleted"
ASSET_STATUS_AI_TRASHED = "ai_trashed"
ASSET_STATUS_USER_TRASHED = "user_trashed"

ASSET_SYNC_PENDING = "pending"
ASSET_SYNC_SYNCED = "synced"
ASSET_SYNC_UNSUPPORTED = "unsupported"

ASSET_CREATE_UPLOAD_AUDIT_ACTION = "asset.create_upload_intent"
ASSET_REGISTER_EXTERNAL_AUDIT_ACTION = "asset.register_external_url"
ASSET_UPLOAD_COMPLETE_AUDIT_ACTION = "asset.upload_complete"
ASSET_UPDATE_METADATA_AUDIT_ACTION = "asset.update_metadata"
ASSET_TRASH_AUDIT_ACTION = "asset.trash"
ASSET_PURGE_AUDIT_ACTION = "asset.purge"


def asset_title(asset: Asset) -> str | None:
    return asset.filename


def asset_to_response(asset: Asset) -> AssetResponse:
    return AssetResponse(
        id=asset.id,
        user_id=asset.user_id,
        kind=asset.kind,
        asset_type=asset.asset_type,
        title=asset_title(asset),
        filename=asset.filename,
        mime_type=asset.mime_type,
        size_bytes=asset.size_bytes,
        sha256=asset.sha256,
        storage_provider=asset.storage_provider,
        storage_key=asset.storage_key,
        external_url=asset.external_url,
        external_provider=asset.external_provider,
        visibility=asset.visibility,
        sync_status=asset.sync_status,
        status=asset.status,
        created_at=asset.created_at,
        updated_at=asset.updated_at,
    )


def asset_to_dict(asset: Asset) -> dict:
    return asset_to_response(asset).model_dump(mode="json")


def asset_boundary_contract(asset: Asset) -> dict:
    return {
        "contract_version": ASSET_CONTRACT_VERSION,
        "status_boundary": {
            "current": asset.status,
            "active": ASSET_STATUS_ACTIVE,
            "api_trash": ASSET_STATUS_DELETED,
            "ai_undo_trash": ASSET_STATUS_AI_TRASHED,
            "user_trash": ASSET_STATUS_USER_TRASHED,
        },
        "sync_boundary": {
            "current": asset.sync_status,
            "internal_upload_initial": ASSET_SYNC_PENDING,
            "internal_upload_complete": ASSET_SYNC_SYNCED,
            "external_reference": ASSET_SYNC_SYNCED,
            "unsupported": ASSET_SYNC_UNSUPPORTED,
        },
        "undo_boundary": {
            "supported": True,
            "result_status": ASSET_STATUS_AI_TRASHED,
            "scope": "metadata_only",
        },
        "trash_boundary": {
            "api_delete_status": ASSET_STATUS_DELETED,
            "requires_no_memo_refs": True,
            "physical_blob_delete": "explicit_e2ee_purge",
        },
    }


def asset_metadata(asset: Asset) -> dict:
    return {
        "contract_version": ASSET_CONTRACT_VERSION,
        "asset_id": asset.id,
        "kind": asset.kind,
        "asset_type": asset.asset_type,
        "title": asset_title(asset),
        "filename": asset.filename,
        "mime_type": asset.mime_type,
        "size_bytes": asset.size_bytes,
        "sha256": asset.sha256,
        "storage_provider": asset.storage_provider,
        "storage_key": asset.storage_key,
        "external_url": asset.external_url,
        "external_provider": asset.external_provider,
        "visibility": asset.visibility,
        "status": asset.status,
        "sync_status": asset.sync_status,
        **asset_boundary_contract(asset),
    }


def build_create_upload_url_payload(asset: Asset, upload_url: str) -> dict:
    metadata = asset_metadata(asset)
    return {
        "contract_version": ASSET_CONTRACT_VERSION,
        "asset_id": asset.id,
        "storage_key": asset.storage_key,
        "upload_url": upload_url,
        "upload_intent": {
            "intent_type": "internal_upload",
            "asset_id": asset.id,
            "method": "PUT",
            "url": upload_url,
            "headers": {"content-type": asset.mime_type} if asset.mime_type else {},
            "storage_provider": asset.storage_provider,
            "storage_key": asset.storage_key,
            "next_action": "encrypt_binary_then_upload_and_mark_complete",
            "status": asset.status,
            "sync_status": asset.sync_status,
            "requires_upload_complete": True,
            "requires_client_encryption": True,
            **asset_boundary_contract(asset),
        },
        "metadata": metadata,
        "asset": asset_to_dict(asset),
    }


def build_encrypted_upload_intent_payload(asset: Asset, upload_url: str) -> dict:
    return {
        "contract_version": ASSET_E2EE_CONTRACT_VERSION,
        "asset_id": asset.id,
        "upload_url": upload_url,
        "method": "PUT",
        "headers": {"content-type": "application/octet-stream"},
        "storage_provider": asset.storage_provider,
        "storage_key": asset.storage_key,
        "sync_status": asset.sync_status,
        "requires_client_encryption": True,
        "required_object_magic": ENCRYPTED_ASSET_MAGIC.decode("ascii"),
    }


def build_register_external_url_payload(asset: Asset) -> dict:
    metadata = asset_metadata(asset)
    return {
        "contract_version": ASSET_CONTRACT_VERSION,
        "asset_id": asset.id,
        "external_url": asset.external_url,
        "external_provider": asset.external_provider,
        "external_registration": {
            "intent_type": "external_reference",
            "asset_id": asset.id,
            "url": asset.external_url,
            "provider": asset.external_provider,
            "status": asset.status,
            "sync_status": asset.sync_status,
            "requires_upload_complete": False,
            **asset_boundary_contract(asset),
        },
        "metadata": metadata,
        "asset": asset_to_dict(asset),
    }


async def write_asset_audit(
    db: AsyncSession,
    *,
    user_id: str,
    action: str,
    asset: Asset,
    before: dict | None = None,
    after: dict | None = None,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> None:
    """Persist operational audit metadata only.

    User-content snapshots and source text belong in the client E2EE audit
    envelope. The cloud audit row intentionally cannot reconstruct them.
    """

    del before, after, source_text
    log = AuditLog(
        user_id=user_id,
        actor_type=actor_type,
        action=action,
        entity_type="asset",
        entity_id=asset.id,
        before_snapshot=None,
        after_snapshot=None,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=None,
        request_id=request_id,
    )
    db.add(log)


async def create_encrypted_asset_upload_record(
    db: AsyncSession,
    *,
    user_id: str,
    asset_id: str | None = None,
) -> tuple[Asset, str]:
    resolved_asset_id = asset_id or str(uuid.uuid4())
    storage_key = f"attachments/{user_id}/{resolved_asset_id}/payload.e2ee"
    asset = Asset(
        id=resolved_asset_id,
        user_id=user_id,
        kind=ASSET_KIND_INTERNAL,
        asset_type="file",
        filename=None,
        mime_type="application/octet-stream",
        size_bytes=None,
        sha256=None,
        storage_provider="minio",
        storage_key=storage_key,
        external_url=None,
        external_provider=None,
        sync_status=ASSET_SYNC_PENDING,
        status=ASSET_STATUS_ACTIVE,
        visibility="private",
    )
    db.add(asset)
    await db.flush()
    return asset, generate_upload_url(storage_key)


async def create_internal_asset_upload_record(
    db: AsyncSession,
    data: AssetCreateUploadUrl,
    *,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> tuple[Asset, str]:
    """Legacy call seam retained for MCP callers, but no plaintext metadata persists."""

    del data, source_text
    asset, upload_url = await create_encrypted_asset_upload_record(db, user_id=user_id)
    await write_asset_audit(
        db,
        user_id=user_id,
        action=ASSET_CREATE_UPLOAD_AUDIT_ACTION,
        asset=asset,
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        request_id=request_id,
    )
    return asset, upload_url


async def register_external_asset_record(
    db: AsyncSession,
    data: AssetRegisterExternalUrl,
    *,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> Asset:
    del db, data, user_id, actor_type, source_channel, tool_name, source_text, request_id
    raise ValueError(
        "Plaintext external asset registration is disabled; sync the URL inside an encrypted asset entity"
    )


def encrypted_asset_object_has_valid_header(storage_key: str) -> bool:
    response = get_storage().get_object(settings.minio_bucket, storage_key)
    try:
        prefix = response.read(len(ENCRYPTED_ASSET_MAGIC))
    finally:
        response.close()
        response.release_conn()
    return prefix == ENCRYPTED_ASSET_MAGIC


def purge_encrypted_asset_object(storage_key: str) -> None:
    get_storage().remove_object(settings.minio_bucket, storage_key)
