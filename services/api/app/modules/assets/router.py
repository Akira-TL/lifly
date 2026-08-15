from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import AuthenticatedSubject
from app.core.storage import check_object_exists, generate_download_url
from app.db.models import Asset, MemoAssetRef
from app.modules.assets.contracts import (
    EncryptedAssetReserveRequest,
    EncryptedAssetUploadCompleteRequest,
)
from app.modules.assets.service import (
    ASSET_PURGE_AUDIT_ACTION,
    ASSET_STATUS_DELETED,
    ASSET_SYNC_SYNCED,
    ASSET_TRASH_AUDIT_ACTION,
    ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
    asset_to_response,
    build_encrypted_upload_intent_payload,
    create_encrypted_asset_upload_record,
    encrypted_asset_object_has_valid_header,
    purge_encrypted_asset_object,
    write_asset_audit,
)
from app.modules.auth.sessions import get_active_subject
from app.schemas.common import (
    ApiResponse,
    AssetUploadCompleteRequest,
    AssetUpdate,
    PaginatedResponse,
)

router = APIRouter()


async def _owned_asset(
    db: AsyncSession,
    *,
    asset_id: str,
    account_id: str,
) -> Asset:
    result = await db.execute(
        select(Asset).where(Asset.id == asset_id, Asset.user_id == account_id)
    )
    asset = result.scalar_one_or_none()
    if asset is None:
        raise HTTPException(status_code=404, detail="Asset not found")
    return asset


async def _memo_ref_count(db: AsyncSession, asset_id: str) -> int:
    count = await db.scalar(
        select(func.count()).select_from(
            select(MemoAssetRef).where(MemoAssetRef.asset_id == asset_id).subquery()
        )
    )
    return int(count or 0)


@router.post("/e2ee/create-upload-url", response_model=ApiResponse)
async def create_e2ee_upload_url(
    data: EncryptedAssetReserveRequest,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset, upload_url = await create_encrypted_asset_upload_record(
        db,
        user_id=subject.account_id,
        asset_id=data.asset_id,
    )
    await write_asset_audit(
        db,
        user_id=subject.account_id,
        action="asset.create_encrypted_upload_intent",
        asset=asset,
        actor_type="user",
        source_channel="api",
        request_id=subject.device_id,
    )
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=build_encrypted_upload_intent_payload(asset, upload_url))


@router.post("/create-upload-url", response_model=ApiResponse, deprecated=True)
async def create_upload_url() -> ApiResponse:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Plaintext attachment upload intents are disabled; use /assets/e2ee/create-upload-url",
    )


@router.post("/register-external-url", response_model=ApiResponse, deprecated=True)
async def register_external_url() -> ApiResponse:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Plaintext external asset registration is disabled; sync the URL inside an encrypted asset entity",
    )


@router.post("/e2ee/{asset_id}/upload-complete", response_model=ApiResponse)
async def e2ee_upload_complete(
    asset_id: str,
    data: EncryptedAssetUploadCompleteRequest,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    if asset.kind != "internal" or not asset.storage_key:
        raise HTTPException(status_code=400, detail="Encrypted upload is only valid for internal assets")
    if not check_object_exists(asset.storage_key):
        raise HTTPException(status_code=400, detail="Encrypted object not found in storage")
    if not encrypted_asset_object_has_valid_header(asset.storage_key):
        raise HTTPException(
            status_code=400,
            detail="Object is not a Lifly encrypted attachment payload",
        )

    asset.sha256 = data.ciphertext_sha256
    asset.size_bytes = data.ciphertext_size_bytes
    asset.sync_status = ASSET_SYNC_SYNCED
    await write_asset_audit(
        db,
        user_id=subject.account_id,
        action=ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
        asset=asset,
        actor_type="user",
        source_channel="api",
        request_id=subject.device_id,
    )
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.post("/{asset_id}/upload-complete", response_model=ApiResponse, deprecated=True)
async def upload_complete(
    asset_id: str,
    data: AssetUploadCompleteRequest,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    if asset.kind != "internal" or not asset.storage_key:
        raise HTTPException(status_code=400, detail="upload-complete only valid for internal assets")
    if not check_object_exists(asset.storage_key):
        raise HTTPException(status_code=400, detail="Encrypted object not found in storage")
    if not encrypted_asset_object_has_valid_header(asset.storage_key):
        raise HTTPException(
            status_code=400,
            detail="Plaintext attachment uploads are disabled",
        )

    if data.sha256:
        asset.sha256 = data.sha256
    if data.size_bytes is not None:
        asset.size_bytes = data.size_bytes
    asset.sync_status = ASSET_SYNC_SYNCED
    await write_asset_audit(
        db,
        user_id=subject.account_id,
        action=ASSET_UPLOAD_COMPLETE_AUDIT_ACTION,
        asset=asset,
        actor_type="user",
        source_channel="api",
        request_id=subject.device_id,
    )
    await db.commit()
    await db.refresh(asset)
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.get("/{asset_id}/download-url", response_model=ApiResponse)
async def get_download_url(
    asset_id: str,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    if asset.kind != "internal" or not asset.storage_key:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail="External asset URLs are stored only inside the encrypted asset entity",
        )
    return ApiResponse(
        data={
            "url": generate_download_url(asset.storage_key),
            "kind": "internal",
            "encrypted": True,
        }
    )


@router.get("", response_model=ApiResponse)
async def list_assets(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    kind: str | None = Query(default=None),
    asset_type: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    query = select(Asset).where(
        Asset.user_id == subject.account_id,
        Asset.status == "active",
    )
    if kind:
        query = query.where(Asset.kind == kind)
    if asset_type:
        query = query.where(Asset.asset_type == asset_type)

    total = await db.scalar(select(func.count()).select_from(query.subquery()))
    result = await db.execute(
        query.order_by(Asset.created_at.desc()).limit(limit).offset(offset)
    )
    assets = result.scalars().all()
    return ApiResponse(
        data=PaginatedResponse(
            total=total or 0,
            limit=limit,
            offset=offset,
            items=[asset_to_response(item).model_dump(mode="json") for item in assets],
        ).model_dump()
    )


@router.get("/{asset_id}", response_model=ApiResponse)
async def get_asset(
    asset_id: str,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    return ApiResponse(data=asset_to_response(asset).model_dump(mode="json"))


@router.put("/{asset_id}", response_model=ApiResponse, deprecated=True)
async def update_asset(
    asset_id: str,
    data: AssetUpdate,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    del data
    await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Sensitive asset metadata must be updated through the encrypted asset entity",
    )


@router.delete("/{asset_id}", response_model=ApiResponse)
async def delete_asset(
    asset_id: str,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    ref_count = await _memo_ref_count(db, asset_id)
    if ref_count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Asset is referenced by {ref_count} legacy memo refs — remove references first",
        )

    asset.status = ASSET_STATUS_DELETED
    await write_asset_audit(
        db,
        user_id=subject.account_id,
        action=ASSET_TRASH_AUDIT_ACTION,
        asset=asset,
        actor_type="user",
        source_channel="api",
        request_id=subject.device_id,
    )
    await db.commit()
    return ApiResponse(data={"id": asset_id, "status": ASSET_STATUS_DELETED})


@router.delete("/e2ee/{asset_id}/purge", response_model=ApiResponse)
async def purge_asset(
    asset_id: str,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> ApiResponse:
    asset = await _owned_asset(db, asset_id=asset_id, account_id=subject.account_id)
    if asset.status == "active":
        raise HTTPException(
            status_code=409,
            detail="Trash the encrypted asset entity before physical purge",
        )
    ref_count = await _memo_ref_count(db, asset_id)
    if ref_count > 0:
        raise HTTPException(
            status_code=409,
            detail=f"Asset still has {ref_count} legacy memo refs",
        )

    storage_key = asset.storage_key
    if storage_key:
        purge_encrypted_asset_object(storage_key)
    await write_asset_audit(
        db,
        user_id=subject.account_id,
        action=ASSET_PURGE_AUDIT_ACTION,
        asset=asset,
        actor_type="user",
        source_channel="api",
        request_id=subject.device_id,
    )
    await db.delete(asset)
    await db.commit()
    return ApiResponse(
        data={
            "id": asset_id,
            "status": "purged",
            "ciphertext_object_deleted": bool(storage_key),
        }
    )
