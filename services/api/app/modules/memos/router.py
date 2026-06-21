from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, delete as sa_delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Memo, AuditLog
from app.schemas.common import (
    MemoCreate,
    MemoUpdate,
    MemoResponse,
    PaginationParams,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


async def _write_audit(
    db: AsyncSession,
    user_id: str,
    action: str,
    entity_type: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    source: str | None = None,
):
    log = AuditLog(
        user_id=user_id,
        actor_type="user",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source or "api",
    )
    db.add(log)


def _memo_to_response(memo: Memo) -> MemoResponse:
    return MemoResponse(
        id=memo.id,
        user_id=memo.user_id,
        type=memo.type,
        title=memo.title,
        content_markdown=memo.content_markdown,
        tags=memo.tags,
        mood=memo.mood,
        status=memo.status,
        created_at=memo.created_at,
        updated_at=memo.updated_at,
    )


@router.post("", response_model=ApiResponse)
async def create_memo(data: MemoCreate, db: AsyncSession = Depends(get_db)):
    memo = Memo(
        user_id="local-dev",
        type=data.type,
        title=data.title,
        content_markdown=data.content_markdown,
        tags=data.tags,
        mood=data.mood,
        source_capture_id=data.source_capture_id,
        source=data.source or "manual",
    )
    db.add(memo)
    await db.flush()
    await _write_audit(db, "local-dev", "create", "memo", memo.id, after=json_serialize(_memo_to_response(memo).model_dump()))
    await db.commit()
    await db.refresh(memo)
    return ApiResponse(data=_memo_to_response(memo).model_dump())


@router.get("", response_model=ApiResponse)
async def list_memos(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    type: str | None = Query(default=None),
    status: str = Query(default="active"),
    q: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    query = select(Memo).where(Memo.user_id == "local-dev", Memo.status == status)
    if type:
        query = query.where(Memo.type == type)
    if q:
        query = query.where(Memo.content_markdown.ilike(f"%{q}%"))

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
            items=[_memo_to_response(m).model_dump() for m in memos],
        ).model_dump()
    )


@router.get("/{memo_id}", response_model=ApiResponse)
async def get_memo(memo_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == "local-dev")
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")
    return ApiResponse(data=_memo_to_response(memo).model_dump())


@router.put("/{memo_id}", response_model=ApiResponse)
async def update_memo(memo_id: str, data: MemoUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == "local-dev")
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")

    before = _memo_to_response(memo).model_dump()
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(memo, key, value)
    memo.revision += 1

    await _write_audit(db, "local-dev", "update", "memo", memo_id, before=json_serialize(before), after=json_serialize(_memo_to_response(memo).model_dump()))
    await db.commit()
    await db.refresh(memo)
    return ApiResponse(data=_memo_to_response(memo).model_dump())


@router.delete("/{memo_id}", response_model=ApiResponse)
async def delete_memo(memo_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Memo).where(Memo.id == memo_id, Memo.user_id == "local-dev")
    )
    memo = result.scalar_one_or_none()
    if not memo:
        raise HTTPException(status_code=404, detail="Memo not found")

    before = _memo_to_response(memo).model_dump()
    memo.status = "user_trashed"
    memo.deleted_at = datetime.now(timezone.utc)
    memo.revision += 1

    await _write_audit(db, "local-dev", "trash", "memo", memo_id, before=json_serialize(before))
    await db.commit()
    return ApiResponse(data={"id": memo_id, "status": "user_trashed"})
