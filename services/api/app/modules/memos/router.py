from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Asset, Memo, MemoAssetRef, MemoClassification, TagMetadata
from app.modules.assets.service import asset_to_response
from app.modules.memos.classification_engine import (
    ensure_tag_metadata,
    generate_memo_classifications,
)
from app.modules.auth.sessions import get_active_account_id
from app.modules.memos.service import (
    create_memo_record,
    memo_to_response,
    write_memo_audit,
)
from app.schemas.common import (
    MemoAssetBindRequest,
    MemoClassificationGenerateRequest,
    MemoCreate,
    MemoUpdate,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


def _memo_data(memo: Memo, *, assets: list[dict] | None = None) -> dict:
    data = memo_to_response(memo).model_dump()
    data["assets"] = assets or []
    return data


def _classification_data(item: MemoClassification) -> dict:
    return {
        "id": item.id,
        "memo_id": item.memo_id,
        "tag": item.tag,
        "source": item.source,
        "status": item.status,
        "confidence": float(item.confidence) if item.confidence is not None else None,
        "reason": item.reason,
        "created_at": item.created_at.isoformat() if item.created_at else None,
        "updated_at": item.updated_at.isoformat() if item.updated_at else None,
        "confirmed_at": item.confirmed_at.isoformat() if item.confirmed_at else None,
    }


def _asset_ref_data(ref: MemoAssetRef, asset: Asset) -> dict:
    return {
        "id": ref.id,
        "memo_id": ref.memo_id,
        "asset_id": ref.asset_id,
        "ref_type": ref.ref_type,
        "position_hint": ref.position_hint,
        "created_at": ref.created_at.isoformat() if ref.created_at else None,
        "asset": asset_to_response(asset).model_dump(mode="json"),
    }


def _tag_metadata_data(item: TagMetadata) -> dict:
    return {
        "id": item.id,
        "name": item.name,
        "kind": item.kind,
        "color_token": item.color_token,
        "icon_token": item.icon_token,
        "sort_order": item.sort_order,
        "status": item.status,
        "created_at": item.created_at.isoformat() if item.created_at else None,
        "updated_at": item.updated_at.isoformat() if item.updated_at else None,
    }


async def _load_memo(db: AsyncSession, memo_id: str, user_id: str) -> Memo:
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == user_id)
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")
    return memo


async def _load_classification(
    db: AsyncSession,
    classification_id: str,
    user_id: str,
    memo_id: str | None = None,
) -> MemoClassification:
    query = select(MemoClassification).where(
        MemoClassification.id == classification_id,
        MemoClassification.user_id == user_id,
    )
    if memo_id:
        query = query.where(MemoClassification.memo_id == memo_id)
    result = await db.execute(query)
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail="Memo classification not found")
    return item


async def _upsert_classification(
    db: AsyncSession,
    memo_id: str,
    data: dict,
    status: str,
    user_id: str,
) -> MemoClassification:
    await _load_memo(db, memo_id, user_id)
    classification_id = data.get("classification_id") or data.get("id")
    if classification_id:
        item = await _load_classification(db, str(classification_id), user_id, memo_id)
        await ensure_tag_metadata(db, user_id=user_id, tag=item.tag)
    else:
        tag = str(data.get("tag") or "").strip()
        if not tag:
            raise HTTPException(status_code=400, detail="tag is required")
        await ensure_tag_metadata(db, user_id=user_id, tag=tag)
        item = MemoClassification(
            user_id=user_id,
            memo_id=memo_id,
            tag=tag,
            source=str(data.get("source") or "user"),
            confidence=data.get("confidence"),
            reason=data.get("reason"),
        )
        db.add(item)
    item.status = status
    if status == "confirmed":
        item.confirmed_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(item)
    return item


async def _load_active_asset(db: AsyncSession, asset_id: str, user_id: str) -> Asset:
    result = await db.execute(
        select(Asset).where(
            Asset.id == asset_id,
            Asset.user_id == user_id,
            Asset.status == "active",
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    return asset


async def _list_memo_asset_refs(db: AsyncSession, memo_id: str, user_id: str) -> list[dict]:
    result = await db.execute(
        select(MemoAssetRef, Asset)
        .join(Asset, MemoAssetRef.asset_id == Asset.id)
        .where(
            MemoAssetRef.memo_id == memo_id,
            Asset.user_id == user_id,
            Asset.status == "active",
        )
        .order_by(MemoAssetRef.created_at.asc())
    )
    return [_asset_ref_data(ref, asset) for ref, asset in result.all()]


@router.post("", response_model=ApiResponse)
async def create_memo(
    data: MemoCreate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await create_memo_record(
        db,
        data,
        user_id=user_id,
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(memo)
    return ApiResponse(data=memo_to_response(memo).model_dump())


@router.get("", response_model=ApiResponse)
async def list_memos(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    type: str | None = Query(default=None),
    status: str = Query(default="active"),
    q: str | None = Query(default=None),
    tag: str | None = Query(default=None),
    classification_status: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    query = select(Memo).where(Memo.user_id == user_id, Memo.status == status)
    if type:
        query = query.where(Memo.type == type)
    if q:
        query = query.where(
            Memo.title.ilike(f"%{q}%") | Memo.content_markdown.ilike(f"%{q}%")
        )
    if tag or classification_status:
        classification_query = select(MemoClassification.memo_id).where(
            MemoClassification.user_id == user_id,
            MemoClassification.status != "rejected",
        )
        if tag:
            classification_query = classification_query.where(MemoClassification.tag == tag)
        if classification_status:
            classification_query = classification_query.where(
                MemoClassification.status == classification_status
            )
        query = query.where(Memo.id.in_(classification_query))

    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query)

    query = query.order_by(Memo.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    memos = result.scalars().all()

    return ApiResponse(
        data=PaginatedResponse(
            total=total or 0,
            limit=limit,
            offset=offset,
            items=[memo_to_response(m).model_dump() for m in memos],
        ).model_dump()
    )


@router.get("/{memo_id}/classifications", response_model=ApiResponse)
async def list_memo_classifications(
    memo_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    await _load_memo(db, memo_id, user_id)
    result = await db.execute(
        select(MemoClassification)
        .where(
            MemoClassification.user_id == user_id,
            MemoClassification.memo_id == memo_id,
        )
        .order_by(MemoClassification.updated_at.desc())
    )
    return ApiResponse(data=[_classification_data(item) for item in result.scalars().all()])


@router.post("/{memo_id}/classifications/generate", response_model=ApiResponse)
async def generate_memo_classification_suggestions(
    memo_id: str,
    data: MemoClassificationGenerateRequest = Body(default_factory=MemoClassificationGenerateRequest),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)
    items = await generate_memo_classifications(
        db,
        memo,
        replace_suggested=data.replace_suggested,
        include_user_tags=data.include_user_tags,
    )
    await db.commit()
    return ApiResponse(data=[_classification_data(item) for item in items])


@router.post("/{memo_id}/classifications/confirm", response_model=ApiResponse)
async def confirm_memo_classification(
    memo_id: str,
    data: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    item = await _upsert_classification(db, memo_id, data, "confirmed", user_id)
    return ApiResponse(data=_classification_data(item))


@router.post("/{memo_id}/classifications/reject", response_model=ApiResponse)
async def reject_memo_classification(
    memo_id: str,
    data: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    item = await _upsert_classification(db, memo_id, data, "rejected", user_id)
    return ApiResponse(data=_classification_data(item))


@router.get("/{memo_id}", response_model=ApiResponse)
async def get_memo(
    memo_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)
    assets = await _list_memo_asset_refs(db, memo_id, user_id)
    return ApiResponse(data=_memo_data(memo, assets=assets))


@router.get("/{memo_id}/assets", response_model=ApiResponse)
async def list_memo_assets(
    memo_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    await _load_memo(db, memo_id, user_id)
    assets = await _list_memo_asset_refs(db, memo_id, user_id)
    return ApiResponse(data={"memo_id": memo_id, "assets": assets})


@router.post("/{memo_id}/assets", response_model=ApiResponse)
async def bind_memo_asset(
    memo_id: str,
    data: MemoAssetBindRequest,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)
    asset = await _load_active_asset(db, data.asset_id, user_id)
    before = _memo_data(
        memo,
        assets=await _list_memo_asset_refs(db, memo_id, user_id),
    )

    existing_result = await db.execute(
        select(MemoAssetRef).where(
            MemoAssetRef.memo_id == memo_id,
            MemoAssetRef.asset_id == data.asset_id,
        )
    )
    ref = existing_result.scalar_one_or_none()
    if ref:
        ref.ref_type = data.ref_type
        ref.position_hint = data.position_hint
    else:
        ref = MemoAssetRef(
            memo_id=memo_id,
            asset_id=data.asset_id,
            ref_type=data.ref_type,
            position_hint=data.position_hint,
        )
        db.add(ref)
    await db.flush()

    after_assets = await _list_memo_asset_refs(db, memo_id, user_id)
    await write_memo_audit(
        db,
        user_id=user_id,
        actor_type="user",
        action="bind_asset",
        entity_id=memo_id,
        before=json_serialize(before),
        after=json_serialize(_memo_data(memo, assets=after_assets)),
        source_channel="api",
        source_text=data.asset_id,
    )
    await db.commit()
    await db.refresh(ref)
    return ApiResponse(
        data={
            "memo_id": memo_id,
            "asset_ref": _asset_ref_data(ref, asset),
            "assets": await _list_memo_asset_refs(db, memo_id, user_id),
        }
    )


@router.delete("/{memo_id}/assets/{asset_id}", response_model=ApiResponse)
async def unbind_memo_asset(
    memo_id: str,
    asset_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)
    before = _memo_data(
        memo,
        assets=await _list_memo_asset_refs(db, memo_id, user_id),
    )

    result = await db.execute(
        select(MemoAssetRef).where(
            MemoAssetRef.memo_id == memo_id,
            MemoAssetRef.asset_id == asset_id,
        )
    )
    ref = result.scalar_one_or_none()
    if not ref:
        raise HTTPException(status_code=404, detail="Memo asset reference not found")

    await db.delete(ref)
    await db.flush()
    after_assets = await _list_memo_asset_refs(db, memo_id, user_id)
    await write_memo_audit(
        db,
        user_id=user_id,
        actor_type="user",
        action="unbind_asset",
        entity_id=memo_id,
        before=json_serialize(before),
        after=json_serialize(_memo_data(memo, assets=after_assets)),
        source_channel="api",
        source_text=asset_id,
    )
    await db.commit()
    return ApiResponse(data={"memo_id": memo_id, "asset_id": asset_id, "status": "unbound"})


@router.put("/{memo_id}", response_model=ApiResponse)
async def update_memo(
    memo_id: str,
    data: MemoUpdate,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)

    before = memo_to_response(memo).model_dump()
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(memo, key, value)
    memo.revision += 1

    await write_memo_audit(
        db,
        user_id=user_id,
        actor_type="user",
        action="update",
        entity_id=memo_id,
        before=json_serialize(before),
        after=json_serialize(memo_to_response(memo).model_dump()),
        source_channel="api",
    )
    await db.commit()
    await db.refresh(memo)
    return ApiResponse(data=memo_to_response(memo).model_dump())


@router.delete("/{memo_id}", response_model=ApiResponse)
async def delete_memo(
    memo_id: str,
    db: AsyncSession = Depends(get_db),
    user_id: str = Depends(get_active_account_id),
):
    memo = await _load_memo(db, memo_id, user_id)

    before = memo_to_response(memo).model_dump()
    memo.status = "user_trashed"
    memo.deleted_at = datetime.now(timezone.utc)
    memo.revision += 1

    await write_memo_audit(
        db,
        user_id=user_id,
        actor_type="user",
        action="trash",
        entity_id=memo_id,
        before=json_serialize(before),
        source_channel="api",
    )
    await db.commit()
    return ApiResponse(data={"id": memo_id, "status": "user_trashed"})
