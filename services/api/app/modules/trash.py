from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import AuditLog, LedgerTransaction, Memo, Task, Tombstone
from app.schemas.common import ApiResponse

router = APIRouter()


@router.get("/audit")
async def list_audit_logs(
    entity_type: str | None = Query(default=None),
    actor_type: str | None = Query(default=None),
    source_channel: str | None = Query(default=None),
    tool_name: str | None = Query(default=None),
    request_id: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    query = select(AuditLog).where(AuditLog.user_id == "local-dev")
    if entity_type:
        query = query.where(AuditLog.entity_type == entity_type)
    if actor_type:
        query = query.where(AuditLog.actor_type == actor_type)
    if source_channel:
        query = query.where(AuditLog.source_channel == source_channel)
    if tool_name:
        query = query.where(AuditLog.tool_name == tool_name)
    if request_id:
        query = query.where(AuditLog.request_id == request_id)

    count_result = await db.execute(
        select(func.count()).select_from(query.subquery())
    )
    total = count_result.scalar() or 0

    query = query.order_by(AuditLog.created_at.desc()).offset(offset).limit(limit)
    result = await db.execute(query)
    logs = result.scalars().all()
    return ApiResponse(data={
        "total": total,
        "limit": limit,
        "offset": offset,
        "items": [{
            "id": log.id,
            "actor_type": log.actor_type,
            "action": log.action,
            "entity_type": log.entity_type,
            "entity_id": log.entity_id,
            "tool_name": log.tool_name,
            "source_channel": log.source_channel,
            "request_id": log.request_id,
            "has_before_snapshot": log.before_snapshot is not None,
            "has_after_snapshot": log.after_snapshot is not None,
            "created_at": log.created_at.isoformat(),
        } for log in logs],
    })


@router.get("/audit/ai-summary")
async def ai_audit_summary(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(
            AuditLog.source_channel,
            AuditLog.tool_name,
            func.count().label("count"),
        )
        .where(
            AuditLog.user_id == "local-dev",
            AuditLog.actor_type == "ai",
        )
        .group_by(AuditLog.source_channel, AuditLog.tool_name)
    )
    rows = result.all()
    return ApiResponse(data={
        "actor_type": "ai",
        "items": [
            {
                "source_channel": row.source_channel,
                "tool_name": row.tool_name,
                "count": row.count,
            }
            for row in rows
        ],
    })


# ─── Trash ───────────────────────────────────────────────────────────────────

TRASHABLE_MODELS = {"memo": Memo, "ledger_transaction": LedgerTransaction, "task": Task}


@router.get("/trash")
async def list_trash(
    entity_type: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    items = []
    types = [entity_type] if entity_type else list(TRASHABLE_MODELS.keys())
    for etype in types:
        model = TRASHABLE_MODELS.get(etype)
        if not model:
            continue
        result = await db.execute(
            select(model).where(
                getattr(model, "user_id") == "local-dev",
                getattr(model, "status").in_(["user_trashed", "ai_trashed"]),
            )
        )
        for obj in result.scalars().all():
            items.append({
                "entity_type": etype,
                "entity_id": obj.id,
                "title": getattr(obj, "title", str(getattr(obj, "id", ""))),
                "status": obj.status,
                "deleted_at": getattr(obj, "deleted_at", None),
            })
    total = len(items)
    return ApiResponse(data={"total": total, "items": items[offset:offset + limit]})


@router.post("/trash/{entity_type}/{entity_id}/restore")
async def restore(entity_type: str, entity_id: str, db: AsyncSession = Depends(get_db)):
    model = TRASHABLE_MODELS.get(entity_type)
    if not model:
        raise HTTPException(status_code=400, detail="Invalid entity type")
    result = await db.execute(
        select(model).where(getattr(model, "id") == entity_id, getattr(model, "user_id") == "local-dev")
    )
    obj = result.scalar_one_or_none()
    if not obj:
        raise HTTPException(status_code=404)
    obj.status = "active"
    obj.deleted_at = None
    await db.commit()
    return ApiResponse(data={"entity_type": entity_type, "entity_id": entity_id, "status": "active"})


@router.post("/trash/purge")
async def purge_all(db: AsyncSession = Depends(get_db)):
    now = datetime.now(timezone.utc)
    purged = 0
    for etype, model in TRASHABLE_MODELS.items():
        result = await db.execute(
            select(model).where(
                getattr(model, "user_id") == "local-dev",
                getattr(model, "status").in_(["user_trashed", "ai_trashed"]),
            )
        )
        for obj in result.scalars().all():
            tombstone = Tombstone(
                user_id="local-dev",
                entity_type=etype,
                entity_id=obj.id,
                purged_at=now,
                last_revision=getattr(obj, "revision", 1),
            )
            db.add(tombstone)
            await db.delete(obj)
            purged += 1
    await db.commit()
    return ApiResponse(data={"purged": purged})
