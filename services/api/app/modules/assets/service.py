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


def asset_to_response(asset: Asset) -> AssetResponse:
    return AssetResponse(
        id=asset.id,
        user_id=asset.user_id,
        kind=asset.kind,
        asset_type=asset.asset_type,
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
        kind="internal",
        asset_type=data.asset_type,
        filename=data.filename,
        mime_type=data.mime_type,
        size_bytes=data.size_bytes,
        storage_provider="minio",
        storage_key=storage_key,
        sync_status="pending",
        visibility="private",
    )
    db.add(asset)
    await db.flush()

    upload_url = generate_upload_url(storage_key)
    await write_asset_audit(
        db,
        user_id=user_id,
        action="create",
        asset=asset,
        after=asset_to_dict(asset),
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
        kind="external",
        asset_type=data.asset_type,
        external_url=data.external_url,
        external_provider=data.external_provider,
        filename=data.title,
        sync_status="synced",
        visibility="private",
    )
    db.add(asset)
    await db.flush()

    await write_asset_audit(
        db,
        user_id=user_id,
        action="create",
        asset=asset,
        after=asset_to_dict(asset),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text or data.external_url,
        request_id=request_id,
    )
    return asset
