from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Asset, Memo, MemoAssetRef
from app.modules.assets.service import asset_to_response
from app.modules.memos.service import (
    DEFAULT_LOCAL_USER_ID,
    create_memo_record,
    memo_to_response,
    write_memo_audit,
)
from app.schemas.common import (
    MemoAssetBindRequest,
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


async def _load_memo(db: AsyncSession, memo_id: str) -> Memo:
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == DEFAULT_LOCAL_USER_ID)
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")
    return memo


async def _load_active_asset(db: AsyncSession, asset_id: str) -> Asset:
    result = await db.execute(
        select(Asset).where(
            Asset.id == asset_id,
            Asset.user_id == DEFAULT_LOCAL_USER_ID,
            Asset.status == "active",
        )
    )
    asset = result.scalar_one_or_none()
    if not asset:
        raise HTTPException(status_code=404, detail="Asset not found")
    return asset


async def _list_memo_asset_refs(db: AsyncSession, memo_id: str) -> list[dict]:
    result = await db.execute(
        select(MemoAssetRef, Asset)
        .join(Asset, MemoAssetRef.asset_id == Asset.id)
        .where(
            MemoAssetRef.memo_id == memo_id,
            Asset.user_id == DEFAULT_LOCAL_USER_ID,
            Asset.status == "active",
        )
        .order_by(MemoAssetRef.created_at.asc())
    )
    return [_asset_ref_data(ref, asset) for ref, asset in result.all()]


@router.post("", response_model=ApiResponse)
async def create_memo(data: MemoCreate, db: AsyncSession = Depends(get_db)):
    memo = await create_memo_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
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
    db: AsyncSession = Depends(get_db),
):
    query = select(Memo).where(Memo.user_id == DEFAULT_LOCAL_USER_ID, Memo.status == status)
    if type:
        query = query.where(Memo.type == type)
    if q:
        query = query.where(
            Memo.title.ilike(f"%{q}%") | Memo.content_markdown.ilike(f"%{q}%")
        )

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


@router.get("/{memo_id}", response_model=ApiResponse)
async def get_memo(memo_id: str, db: AsyncSession = Depends(get_db)):
    memo = await _load_memo(db, memo_id)
    assets = await _list_memo_asset_refs(db, memo_id)
    return ApiResponse(data=_memo_data(memo, assets=assets))


@router.get("/{memo_id}/assets", response_model=ApiResponse)
async def list_memo_assets(memo_id: str, db: AsyncSession = Depends(get_db)):
    await _load_memo(db, memo_id)
    assets = await _list_memo_asset_refs(db, memo_id)
    return ApiResponse(data={"memo_id": memo_id, "assets": assets})


@router.post("/{memo_id}/assets", response_model=ApiResponse)
async def bind_memo_asset(
    memo_id: str,
    data: MemoAssetBindRequest,
    db: AsyncSession = Depends(get_db),
):
    memo = await _load_memo(db, memo_id)
    asset = await _load_active_asset(db, data.asset_id)
    before = _memo_data(memo, assets=await _list_memo_asset_refs(db, memo_id))

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

    after_assets = await _list_memo_asset_refs(db, memo_id)
    await write_memo_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
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
            "assets": await _list_memo_asset_refs(db, memo_id),
        }
    )


@router.delete("/{memo_id}/assets/{asset_id}", response_model=ApiResponse)
async def unbind_memo_asset(
    memo_id: str,
    asset_id: str,
    db: AsyncSession = Depends(get_db),
):
    memo = await _load_memo(db, memo_id)
    before = _memo_data(memo, assets=await _list_memo_asset_refs(db, memo_id))

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
    after_assets = await _list_memo_asset_refs(db, memo_id)
    await write_memo_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
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
async def update_memo(memo_id: str, data: MemoUpdate, db: AsyncSession = Depends(get_db)):
    memo = await _load_memo(db, memo_id)

    before = memo_to_response(memo).model_dump()
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(memo, key, value)
    memo.revision += 1

    await write_memo_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
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
async def delete_memo(memo_id: str, db: AsyncSession = Depends(get_db)):
    memo = await _load_memo(db, memo_id)

    before = memo_to_response(memo).model_dump()
    memo.status = "user_trashed"
    memo.deleted_at = datetime.now(timezone.utc)
    memo.revision += 1

    await write_memo_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="user",
        action="trash",
        entity_id=memo_id,
        before=json_serialize(before),
        source_channel="api",
    )
    await db.commit()
    return ApiResponse(data={"id": memo_id, "status": "user_trashed"})
