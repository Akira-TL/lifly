from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Memo
from app.modules.memos.service import (
    DEFAULT_LOCAL_USER_ID,
    create_memo_record,
    memo_to_response,
    write_memo_audit,
)
from app.schemas.common import (
    MemoCreate,
    MemoUpdate,
    PaginationParams,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


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
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == DEFAULT_LOCAL_USER_ID)
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")
    return ApiResponse(data=memo_to_response(memo).model_dump())


@router.put("/{memo_id}", response_model=ApiResponse)
async def update_memo(memo_id: str, data: MemoUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == DEFAULT_LOCAL_USER_ID)
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")

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
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == DEFAULT_LOCAL_USER_ID)
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")

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
