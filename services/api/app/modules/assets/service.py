from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.storage import generate_upload_url
from app.db.models import Asset, AuditLog
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    AssetResponse,
)

DEFAULT_LOCAL_USER_ID = "local-dev"

ASSET_CONTRACT_VERSION = "asset.v0.5.1"

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
            "physical_blob_delete": "not_in_v0.5.1",
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
            "next_action": "upload_binary_then_mark_upload_complete",
            "status": asset.status,
            "sync_status": asset.sync_status,
            "requires_upload_complete": True,
            **asset_boundary_contract(asset),
        },
        "metadata": metadata,
        "asset": asset_to_dict(asset),
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
    log = AuditLog(
        user_id=user_id,
        actor_type=actor_type,
        action=action,
        entity_type="asset",
        entity_id=asset.id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
    )
    db.add(log)


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
    asset_id = str(uuid.uuid4())
    storage_key = f"attachments/{user_id}/{asset_id}/{data.filename}"

    asset = Asset(
        id=asset_id,
        user_id=user_id,
        kind=ASSET_KIND_INTERNAL,
        asset_type=data.asset_type,
        filename=data.filename,
        mime_type=data.mime_type,
        size_bytes=data.size_bytes,
        storage_provider="minio",
        storage_key=storage_key,
        sync_status=ASSET_SYNC_PENDING,
        status=ASSET_STATUS_ACTIVE,
        visibility="private",
    )
    db.add(asset)
    await db.flush()

    upload_url = generate_upload_url(storage_key)
    await write_asset_audit(
        db,
        user_id=user_id,
        action=ASSET_CREATE_UPLOAD_AUDIT_ACTION,
        asset=asset,
        after=asset_metadata(asset),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text or data.filename,
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
    asset = Asset(
        user_id=user_id,
        kind=ASSET_KIND_EXTERNAL,
        asset_type=data.asset_type,
        external_url=data.external_url,
        external_provider=data.external_provider,
        filename=data.title,
        sync_status=ASSET_SYNC_SYNCED,
        status=ASSET_STATUS_ACTIVE,
        visibility="private",
    )
    db.add(asset)
    await db.flush()

    await write_asset_audit(
        db,
        user_id=user_id,
        action=ASSET_REGISTER_EXTERNAL_AUDIT_ACTION,
        asset=asset,
        after=asset_metadata(asset),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text or data.external_url,
        request_id=request_id,
    )
    return asset
