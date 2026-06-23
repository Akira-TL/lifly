from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import AuditLog, LedgerTransaction, Memo, Task
from app.modules.assets.service import (
    asset_to_dict,
    create_internal_asset_upload_record,
    register_external_asset_record,
)
from app.modules.ledger.service import (
    create_ledger_transaction_record,
    ledger_transaction_to_dict,
)
from app.modules.memos.service import (
    DEFAULT_LOCAL_USER_ID,
    create_memo_record,
)
from app.modules.mcp.parse_engine import (
    CAPTURE_STORE,
    add_undo_entry,
    get_undo_entries,
    parse_mixed_input,
)
from app.modules.tasks.service import create_task_record, task_to_dict
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    CaptureUndoRequest,
    LedgerTransactionCreate,
    MemoCreate,
    TaskCreate,
    json_serialize,
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
    return ledger_transaction_to_dict(tx)


def _task_dict(task: Task) -> dict:
    return task_to_dict(task)


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
            try:
                data = LedgerTransactionCreate.model_validate({
                    **payload,
                    "direction": payload.get("direction") or "expense",
                    "source": payload.get("source") or "ai",
                    "source_capture_id": capture_id,
                    "confidence": payload.get("confidence") if payload.get("confidence") is not None else act.confidence,
                })
            except ValidationError as exc:
                raise HTTPException(status_code=422, detail=exc.errors()) from exc

            tx = await create_ledger_transaction_record(
                db,
                data,
                user_id=DEFAULT_LOCAL_USER_ID,
                actor_type="ai",
                source_channel="mcp",
                tool_name="capture_commit",
                source_text=body.get("source_text") or act.raw_text,
            )
            created_entities.append({"type": "ledger_transaction", "id": tx.id})

        elif act.type == "task_create":
            try:
                data = TaskCreate.model_validate({
                    **payload,
                    "source": payload.get("source") or "ai",
                    "source_capture_id": capture_id,
                })
            except ValidationError as exc:
                raise HTTPException(status_code=422, detail=exc.errors()) from exc

            task = await create_task_record(
                db,
                data,
                user_id=DEFAULT_LOCAL_USER_ID,
                actor_type="ai",
                source_channel="mcp",
                tool_name="capture_commit",
                source_text=body.get("source_text") or act.raw_text,
            )
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
    try:
        data = CaptureUndoRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    undo_token = data.undo_token
    entries = get_undo_entries(undo_token)
    if not entries:
        raise HTTPException(status_code=404, detail="Undo token not found or expired")

    undone_entities: list[dict] = []
    failed_entities: list[dict] = []

    for entry in entries:
        model_class = {
            "memo": Memo,
            "ledger_transaction": LedgerTransaction,
            "task": Task,
        }.get(entry.entity_type)

        if not model_class:
            failed_entities.append({
                "type": entry.entity_type,
                "id": entry.entity_id,
                "reason": "unsupported_entity_type",
            })
            continue

        result = await db.execute(
            select(model_class).where(
                getattr(model_class, "id") == entry.entity_id,
                getattr(model_class, "user_id") == DEFAULT_LOCAL_USER_ID,
            )
        )
        entity = result.scalar_one_or_none()
        if not entity:
            failed_entities.append({
                "type": entry.entity_type,
                "id": entry.entity_id,
                "reason": "not_found",
            })
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

        await _write_audit(
            db,
            DEFAULT_LOCAL_USER_ID,
            "undo_delete",
            entry.entity_type,
            entry.entity_id,
            before=before_snap,
            tool_name="capture_undo",
            source_text=f"undo_token={undo_token}",
        )
        undone_entities.append({"type": entry.entity_type, "id": entry.entity_id})

    await db.commit()
    return {
        "undone": len(undone_entities),
        "entities": undone_entities,
        "failed_entities": failed_entities,
    }


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
        Memo.user_id == DEFAULT_LOCAL_USER_ID,
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
    try:
        data = LedgerTransactionCreate.model_validate({
            **body,
            "direction": body.get("direction") or "expense",
            "source": body.get("source") or "ai",
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    tx = await create_ledger_transaction_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="ai",
        source_channel="mcp",
        tool_name="expense_create",
        source_text=body.get("source_text") or body.get("note") or body.get("merchant"),
    )
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
        LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
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
    now = datetime.now(timezone.utc)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

    result = await db.execute(
        select(
            func.sum(LedgerTransaction.amount).label("total_expense"),
            func.count().label("count"),
        ).where(
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
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
    try:
        data = TaskCreate.model_validate({
            **body,
            "source": body.get("source") or "ai",
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    task = await create_task_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="ai",
        source_channel="mcp",
        tool_name="task_create",
        source_text=body.get("source_text") or body.get("title") or body.get("description"),
    )
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
        Task.user_id == DEFAULT_LOCAL_USER_ID,
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
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = json_serialize(_task_dict(task))
    task.task_status = "done"
    task.completed_at = datetime.now(timezone.utc)
    task.revision += 1

    await _write_audit(db, DEFAULT_LOCAL_USER_ID, "complete", "task", task_id,
                       before=before, after=json_serialize(_task_dict(task)),
                       tool_name="task_complete")
    await db.commit()
    await db.refresh(task)
    return {"task": _task_dict(task)}


@router.post("/asset/create-upload-url")
async def mcp_asset_create_upload_url(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    try:
        data = AssetCreateUploadUrl.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    asset, upload_url = await create_internal_asset_upload_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="ai",
        source_channel="mcp",
        tool_name="asset_create_upload_url",
        source_text=body.get("source_text") or body.get("filename"),
    )
    await db.commit()
    await db.refresh(asset)

    return {
        "asset_id": asset.id,
        "storage_key": asset.storage_key,
        "upload_url": upload_url,
        "asset": asset_to_dict(asset),
    }


@router.post("/asset/register-external-url")
async def mcp_asset_register_external_url(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    try:
        data = AssetRegisterExternalUrl.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    asset = await register_external_asset_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="ai",
        source_channel="mcp",
        tool_name="asset_register_external_url",
        source_text=body.get("source_text") or body.get("external_url"),
    )
    await db.commit()
    await db.refresh(asset)

    return {"asset": asset_to_dict(asset)}
