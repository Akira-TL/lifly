from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.storage import (
    generate_download_url,
    check_object_exists,
)
from app.db.models import Asset, MemoAssetRef
from app.modules.assets.service import (
    ASSET_STATUS_DELETED,
    ASSET_SYNC_SYNCED,
    ASSET_TRASH_AUDIT_ACTION,
    ASSET_UPDATE_METADATA_AUDIT_ACTION,
    ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
    asset_metadata,
    asset_to_response,
    build_create_upload_url_payload,
    build_register_external_url_payload,
    create_internal_asset_upload_record,
    register_external_asset_record,
    write_asset_audit,
)
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    AssetUploadCompleteRequest,
    AssetUpdate,
    PaginatedResponse,
    ApiResponse,
)

router = APIRouter()


@router.post("/create-upload-url", response_model=ApiResponse)
async def create_upload_url(data: AssetCreateUploadUrl, db: AsyncSession = Depends(get_db)):
    asset, upload_url = await create_internal_asset_upload_record(
        db,
        data,
        user_id="local-dev",
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=build_create_upload_url_payload(asset, upload_url))


@router.post("/register-external-url", response_model=ApiResponse)
async def register_external_url(data: AssetRegisterExternalUrl, db: AsyncSession = Depends(get_db)):
    asset = await register_external_asset_record(
        db,
        data,
        user_id="local-dev",
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=build_register_external_url_payload(asset))


@router.post("/{asset_id}/upload-complete", response_model=ApiResponse)
async def upload_complete(
    asset_id: str,
    data: AssetUploadCompleteRequest,
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    if asset.kind != "internal":
        raise HTTPException(status_code=400, detail="upload-complete only valid for internal assets")

    if not check_object_exists(asset.storage_key):
        raise HTTPException(status_code=400, detail="File not found in storage — upload may not be complete")

    before = asset_metadata(asset)
    if data.sha256:
        asset.sha256 = data.sha256
    if data.size_bytes is not None:
        asset.size_bytes = data.size_bytes
    asset.sync_status = ASSET_SYNC_SYNCED
    after = asset_metadata(asset)
    await write_asset_audit(
        db,
        user_id="local-dev",
        action=ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
        asset=asset,
        before=before,
        after=after,
        actor_type="user",
        source_channel="api",
        source_text=asset_id,
    )

    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.get("/{asset_id}/download-url", response_model=ApiResponse)
async def get_download_url(asset_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    if asset.kind == "external":
        return ApiResponse(data={"url": asset.external_url, "kind": "external"})
    url = generate_download_url(asset.storage_key)
    return ApiResponse(data={"url": url, "kind": "internal"})


@router.get("", response_model=ApiResponse)
async def list_assets(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    kind: str | None = Query(default=None),
    asset_type: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    query = select(Asset).where(Asset.user_id == "local-dev", Asset.status == "active")
    if kind:
        query = query.where(Asset.kind == kind)
    if asset_type:
        query = query.where(Asset.asset_type == asset_type)

    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query)

    query = query.order_by(Asset.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    assets = result.scalars().all()

    return ApiResponse(
        data=PaginatedResponse(
            total=total or 0,
            limit=limit,
            offset=offset,
            items=[asset_to_response(a).model_dump(mode="json") for a in assets],
        ).model_dump()
    )


@router.get("/{asset_id}", response_model=ApiResponse)
async def get_asset(asset_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.put("/{asset_id}", response_model=ApiResponse)
async def update_asset(asset_id: str, data: AssetUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    before = asset_metadata(asset)
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        if key == "title":
            asset.filename = value
        else:
            setattr(asset, key, value)
    after = asset_metadata(asset)
    await write_asset_audit(
        db,
        user_id="local-dev",
        action=ASSET_UPDATE_METADATA_AUDIT_ACTION,
        asset=asset,
        before=before,
        after=after,
        actor_type="user",
        source_channel="api",
        source_text=asset_id,
    )

    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.delete("/{asset_id}", response_model=ApiResponse)
async def delete_asset(asset_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    ref_count = await db.scalar(
        select(func.count()).select_from(
            select(MemoAssetRef).where(MemoAssetRef.asset_id == asset_id).subquery()
        )
    )
    if ref_count and ref_count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Asset is referenced by {ref_count} memos — remove references first",
        )

    before = asset_metadata(asset)
    asset.status = ASSET_STATUS_DELETED
    after = asset_metadata(asset)
    await write_asset_audit(
        db,
        user_id="local-dev",
        action=ASSET_TRASH_AUDIT_ACTION,
        asset=asset,
        before=before,
        after=after,
        actor_type="user",
        source_channel="api",
        source_text=asset_id,
    )

    await db.commit()
    return ApiResponse(data={"id": asset_id, "status": ASSET_STATUS_DELETED})
