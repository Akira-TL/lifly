from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import create_access_token
from app.db.models import (
    Memo,
    LedgerTransaction,
    Task,
    Asset,
    AuditLog,
    MemoAssetRef,
)
from app.modules.memos.service import (
    DEFAULT_LOCAL_USER_ID,
    create_memo_record,
)
from app.schemas.common import MemoCreate, json_serialize
from app.modules.mcp.parse_engine import (
    parse_mixed_input,
    CAPTURE_STORE,
    UNDO_STORE,
    UndoEntry,
    add_undo_entry,
    get_undo_entries,
)

router = APIRouter()

UNDO_TOKENS: dict[str, str] = {}  # undo_token -> capture_id mapping


# ─── Helpers ──────────────────────────────────────────────────────────────────

async def _write_audit(
    db: AsyncSession,
    user_id: str,
    action: str,
    entity_type: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    source: str | None = "mcp",
    tool_name: str | None = None,
    source_text: str | None = None,
):
    log = AuditLog(
        user_id=user_id,
        actor_type="ai",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source,
        tool_name=tool_name,
        source_text=source_text,
    )
    db.add(log)


def _memo_dict(memo: Memo) -> dict:
    return {
        "id": memo.id,
        "user_id": memo.user_id,
        "type": memo.type,
        "title": memo.title,
        "content_markdown": memo.content_markdown,
        "tags": memo.tags,
        "mood": memo.mood,
        "status": memo.status,
        "created_at": memo.created_at.isoformat() if memo.created_at else None,
        "updated_at": memo.updated_at.isoformat() if memo.updated_at else None,
    }


def _tx_dict(tx: LedgerTransaction) -> dict:
    return {
        "id": tx.id,
        "user_id": tx.user_id,
        "direction": tx.direction,
        "amount": float(tx.amount),
        "currency": tx.currency,
        "merchant": tx.merchant,
        "note": tx.note,
        "occurred_at": tx.occurred_at.isoformat() if tx.occurred_at else None,
        "status": tx.status,
        "created_at": tx.created_at.isoformat() if tx.created_at else None,
        "updated_at": tx.updated_at.isoformat() if tx.updated_at else None,
    }


def _task_dict(task: Task) -> dict:
    return {
        "id": task.id,
        "user_id": task.user_id,
        "title": task.title,
        "description": task.description,
        "due_at": task.due_at.isoformat() if task.due_at else None,
        "remind_at": task.remind_at.isoformat() if task.remind_at else None,
        "priority": task.priority,
        "task_status": task.task_status,
        "status": task.status,
        "completed_at": task.completed_at.isoformat() if task.completed_at else None,
        "created_at": task.created_at.isoformat() if task.created_at else None,
        "updated_at": task.updated_at.isoformat() if task.updated_at else None,
    }


# ─── capture_parse ────────────────────────────────────────────────────────────

@router.post("/capture/parse")
async def capture_parse(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    text = body.get("text", "")
    timezone_str = body.get("timezone", "Asia/Shanghai")
    locale = body.get("locale", "zh-CN")

    if not text.strip():
        raise HTTPException(status_code=400, detail="text is required")

    result = parse_mixed_input(text, timezone_str=timezone_str, locale=locale)

    actions_out = []
    for act in result.actions:
        actions_out.append({
            "type": act.type,
            "payload": act.payload,
            "confidence": act.confidence,
        })

    return {
        "capture_id": result.capture_id,
        "actions": actions_out,
        "requires_confirmation": result.requires_confirmation,
    }


# ─── capture_commit ───────────────────────────────────────────────────────────

@router.post("/capture/commit")
async def capture_commit(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    capture_id = body.get("capture_id")
    selected_indexes: list[int] | None = body.get("selected_action_indexes")

    session = CAPTURE_STORE.get(capture_id)
    if not session:
        raise HTTPException(status_code=404, detail="Capture session not found or expired")
    if session.committed:
        raise HTTPException(status_code=409, detail="Capture session already committed")

    actions = session.actions
    if selected_indexes is not None:
        actions = [actions[i] for i in selected_indexes if 0 <= i < len(session.actions)]

    created_entities: list[dict] = []

    for act in actions:
        payload = act.payload

        if act.type == "memo_create":
            try:
                data = MemoCreate.model_validate({
                    **payload,
                    "type": payload.get("type") or "memo",
                    "source": payload.get("source") or "ai",
                    "source_capture_id": capture_id,
                })
            except ValidationError as exc:
                raise HTTPException(status_code=422, detail=exc.errors()) from exc

            memo = await create_memo_record(
                db,
                data,
                user_id=DEFAULT_LOCAL_USER_ID,
                actor_type="ai",
                source_channel="mcp",
                tool_name="capture_commit",
                source_text=body.get("source_text") or act.raw_text,
            )
            created_entities.append({"type": "memo", "id": memo.id})

        elif act.type == "expense_create":
            occurred_at = payload.get("occurred_at")
            if occurred_at and isinstance(occurred_at, str):
                occurred_at = datetime.fromisoformat(occurred_at)

            tx = LedgerTransaction(
                user_id="local-dev",
                direction=payload.get("direction", "expense"),
                amount=payload.get("amount", 0),
                currency=payload.get("currency", "CNY"),
                merchant=payload.get("merchant"),
                category_id=payload.get("category_id"),
                note=payload.get("note"),
                occurred_at=occurred_at or datetime.now(timezone.utc),
                source="ai",
                source_capture_id=capture_id,
                confidence=act.confidence,
            )
            db.add(tx)
            await db.flush()
            await _write_audit(db, "local-dev", "create", "ledger_transaction", tx.id,
                               after=json_serialize(_tx_dict(tx)),
                               tool_name="capture_commit",
                               source_text=act.raw_text)
            created_entities.append({"type": "ledger_transaction", "id": tx.id})

        elif act.type == "task_create":
            remind_at = payload.get("remind_at")
            if remind_at and isinstance(remind_at, str):
                remind_at = datetime.fromisoformat(remind_at)

            task = Task(
                user_id="local-dev",
                title=payload.get("title", ""),
                description=payload.get("description"),
                due_at=payload.get("due_at"),
                remind_at=remind_at,
                priority=payload.get("priority", "normal"),
                source_capture_id=capture_id,
                source="ai",
            )
            db.add(task)
            await db.flush()
            await _write_audit(db, "local-dev", "create", "task", task.id,
                               after=json_serialize(_task_dict(task)),
                               tool_name="capture_commit",
                               source_text=act.raw_text)
            created_entities.append({"type": "task", "id": task.id})

    session.committed = True
    await db.commit()

    undo_token = str(uuid.uuid4())
    for ent in created_entities:
        add_undo_entry(undo_token, ent["type"], ent["id"], "create")
    UNDO_TOKENS[undo_token] = capture_id

    return {
        "committed": True,
        "created_entities": created_entities,
        "undo_token": undo_token,
    }


# ─── capture_undo ────────────────────────────────────────────────────────────

@router.post("/capture/undo")
async def capture_undo(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    undo_token = body.get("undo_token")

    if not undo_token:
        raise HTTPException(status_code=400, detail="undo_token is required")

    entries = get_undo_entries(undo_token)
    if not entries:
        raise HTTPException(status_code=404, detail="Undo token not found or expired")

    undone = 0
    for entry in entries:
        model_class = {
            "memo": Memo,
            "ledger_transaction": LedgerTransaction,
            "task": Task,
        }.get(entry.entity_type)

        if not model_class:
            continue

        result = await db.execute(
            select(model_class).where(
                getattr(model_class, "id") == entry.entity_id,
                getattr(model_class, "user_id") == "local-dev",
            )
        )
        entity = result.scalar_one_or_none()
        if not entity:
            continue

        before_snap = json_serialize(
            _memo_dict(entity) if entry.entity_type == "memo"
            else _tx_dict(entity) if entry.entity_type == "ledger_transaction"
            else _task_dict(entity)
        )

        if hasattr(entity, "status"):
            entity.status = "ai_trashed"
        if hasattr(entity, "deleted_at"):
            entity.deleted_at = datetime.now(timezone.utc)
        if hasattr(entity, "revision"):
            entity.revision += 1

        await _write_audit(db, "local-dev", "undo_delete", entry.entity_type, entry.entity_id,
                           before=before_snap,
                           tool_name="capture_undo",
                           source_text=f"undo_token={undo_token}")
        undone += 1

    await db.commit()
    return {"undone": undone, "entities": [{"type": e.entity_type, "id": e.entity_id} for e in entries]}


# ─── Direct CRUD Tools ────────────────────────────────────────────────────────

@router.post("/memo/create")
async def mcp_memo_create(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    try:
        data = MemoCreate.model_validate({
            **body,
            "source": body.get("source") or "ai",
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    memo = await create_memo_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="ai",
        source_channel="mcp",
        tool_name="memo_create",
        source_text=body.get("source_text") or body.get("content_markdown"),
    )
    await db.commit()
    await db.refresh(memo)

    undo_token = str(uuid.uuid4())
    add_undo_entry(undo_token, "memo", memo.id, "create")

    memo_data = _memo_dict(memo)
    return {
        "memo_id": memo.id,
        "status": memo.status,
        "memo": memo_data,
        "undo_token": undo_token,
    }


@router.post("/memo/search")
async def mcp_memo_search(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    q = body.get("q", "")
    limit = body.get("limit", 20)

    query = select(Memo).where(
        Memo.user_id == "local-dev",
        Memo.status == "active",
    )
    if q:
        query = query.where(
            Memo.title.ilike(f"%{q}%") | Memo.content_markdown.ilike(f"%{q}%")
        )
    query = query.order_by(Memo.created_at.desc()).limit(limit)
    result = await db.execute(query)
    return {"memos": [_memo_dict(m) for m in result.scalars().all()]}


@router.post("/expense/create")
async def mcp_expense_create(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    occurred_at = body.get("occurred_at")
    if occurred_at and isinstance(occurred_at, str):
        occurred_at = datetime.fromisoformat(occurred_at)

    tx = LedgerTransaction(
        user_id="local-dev",
        direction=body.get("direction", "expense"),
        amount=body.get("amount", 0),
        currency=body.get("currency", "CNY"),
        merchant=body.get("merchant"),
        category_id=body.get("category_id"),
        note=body.get("note"),
        occurred_at=occurred_at or datetime.now(timezone.utc),
        source="ai",
    )
    db.add(tx)
    await db.flush()
    await _write_audit(db, "local-dev", "create", "ledger_transaction", tx.id,
                       after=json_serialize(_tx_dict(tx)),
                       tool_name="expense_create")
    await db.commit()
    await db.refresh(tx)

    undo_token = str(uuid.uuid4())
    add_undo_entry(undo_token, "ledger_transaction", tx.id, "create")

    return {"transaction": _tx_dict(tx), "undo_token": undo_token}


@router.post("/expense/search")
async def mcp_expense_search(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    q = body.get("q", "")
    limit = body.get("limit", 20)

    query = select(LedgerTransaction).where(
        LedgerTransaction.user_id == "local-dev",
        LedgerTransaction.status == "active",
    )
    if q:
        query = query.where(
            LedgerTransaction.merchant.ilike(f"%{q}%") | LedgerTransaction.note.ilike(f"%{q}%")
        )
    query = query.order_by(LedgerTransaction.occurred_at.desc()).limit(limit)
    result = await db.execute(query)
    return {"transactions": [_tx_dict(t) for t in result.scalars().all()]}


@router.post("/expense/summary")
async def mcp_expense_summary(request: Request, db: AsyncSession = Depends(get_db)):
    # 当月汇总
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    result = await db.execute(
        select(
            func.sum(LedgerTransaction.amount).label("total_expense"),
            func.count().label("count"),
        ).where(
            LedgerTransaction.user_id == "local-dev",
            LedgerTransaction.direction == "expense",
            LedgerTransaction.status == "active",
            LedgerTransaction.occurred_at >= month_start,
        )
    )
    row = result.one_or_none()
    total = float(row.total_expense or 0) if row else 0
    count = row.count if row else 0

    return {"period": "current_month", "total_expense": total, "count": count}


@router.post("/task/create")
async def mcp_task_create(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    remind_at = body.get("remind_at")
    if remind_at and isinstance(remind_at, str):
        remind_at = datetime.fromisoformat(remind_at)

    task = Task(
        user_id="local-dev",
        title=body.get("title", ""),
        description=body.get("description"),
        due_at=body.get("due_at"),
        remind_at=remind_at,
        priority=body.get("priority", "normal"),
        source="ai",
    )
    db.add(task)
    await db.flush()
    await _write_audit(db, "local-dev", "create", "task", task.id,
                       after=json_serialize(_task_dict(task)),
                       tool_name="task_create")
    await db.commit()
    await db.refresh(task)

    undo_token = str(uuid.uuid4())
    add_undo_entry(undo_token, "task", task.id, "create")

    return {"task": _task_dict(task), "undo_token": undo_token}


@router.post("/task/list")
async def mcp_task_list(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    task_status = body.get("task_status", None)
    limit = body.get("limit", 20)

    query = select(Task).where(
        Task.user_id == "local-dev",
        Task.status == "active",
    )
    if task_status:
        query = query.where(Task.task_status == task_status)
    query = query.order_by(Task.created_at.desc()).limit(limit)
    result = await db.execute(query)
    return {"tasks": [_task_dict(t) for t in result.scalars().all()]}


@router.post("/task/complete")
async def mcp_task_complete(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    task_id = body.get("task_id")

    if not task_id:
        raise HTTPException(status_code=400, detail="task_id is required")

    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == "local-dev")
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = json_serialize(_task_dict(task))
    task.task_status = "done"
    task.completed_at = datetime.now(timezone.utc)
    task.revision += 1

    await _write_audit(db, "local-dev", "complete", "task", task_id,
                       before=before, after=json_serialize(_task_dict(task)),
                       tool_name="task_complete")
    await db.commit()
    await db.refresh(task)
    return {"task": _task_dict(task)}
