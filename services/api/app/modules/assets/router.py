from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.storage import (
    generate_upload_url,
    generate_download_url,
    check_object_exists,
)
from app.db.models import Asset, MemoAssetRef
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    AssetUploadCompleteRequest,
    AssetUpdate,
    AssetResponse,
    PaginatedResponse,
    ApiResponse,
)

router = APIRouter()


def _asset_to_response(asset: Asset) -> AssetResponse:
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


@router.post("/create-upload-url", response_model=ApiResponse)
async def create_upload_url(data: AssetCreateUploadUrl, db: AsyncSession = Depends(get_db)):
    asset_id = str(uuid.uuid4())
    storage_key = f"attachments/local-dev/{asset_id}/{data.filename}"

    asset = Asset(
        id=asset_id,
        user_id="local-dev",
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

    await db.commit()
    return ApiResponse(data={
        "asset_id": asset_id,
        "storage_key": storage_key,
        "upload_url": upload_url,
        "asset": _asset_to_response(asset).model_dump(),
    })


@router.post("/register-external-url", response_model=ApiResponse)
async def register_external_url(data: AssetRegisterExternalUrl, db: AsyncSession = Depends(get_db)):
    asset = Asset(
        user_id="local-dev",
        kind="external",
        asset_type=data.asset_type,
        external_url=data.external_url,
        external_provider=data.external_provider,
        filename=data.title,
        sync_status="synced",
        visibility="private",
    )
    db.add(asset)
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=_asset_to_response(asset).model_dump())


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

    if data.sha256:
        asset.sha256 = data.sha256
    if data.size_bytes is not None:
        asset.size_bytes = data.size_bytes
    asset.sync_status = "synced"

    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=_asset_to_response(asset).model_dump())


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
            items=[_asset_to_response(a).model_dump() for a in assets],
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
    return ApiResponse(data=_asset_to_response(asset).model_dump())


@router.put("/{asset_id}", response_model=ApiResponse)
async def update_asset(asset_id: str, data: AssetUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == "local-dev")
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")

    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(asset, key, value)

    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=_asset_to_response(asset).model_dump())


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

    asset.status = "deleted"
    await db.commit()
    return ApiResponse(data={"id": asset_id, "status": "deleted"})
