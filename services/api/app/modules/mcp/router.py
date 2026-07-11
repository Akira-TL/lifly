from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import ValidationError
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Asset, AuditLog, LedgerTransaction, Memo, Task
from app.modules.assets.service import (
    asset_to_dict,
    build_create_upload_url_payload,
    build_register_external_url_payload,
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
from app.modules.mcp.capture_commit_service import commit_capture_actions
from app.modules.mcp.capture_lifecycle_router import (
    attach_capture_assets,
    router as capture_lifecycle_router,
)
from app.modules.mcp.capture_schemas import CaptureCommitRequest, CaptureParseRequest
from app.modules.mcp.capture_session_service import (
    deserialize_capture_actions,
    get_active_capture_session,
    get_capture_turn,
    get_turn_by_undo_token,
    latest_action_turn,
    mark_capture_session_committed,
    mark_capture_turn_committed,
    mark_capture_turn_undone,
    next_capture_turn_index,
    persist_capture_session,
    persist_capture_turn,
)
from app.modules.mcp.parse_engine import CAPTURE_STORE, parse_mixed_input
from app.modules.mcp.undo_service import consume_undo_entries, list_undo_entries, persist_undo_entries
from app.modules.tasks.service import complete_task_record, create_task_record, task_to_dict
from app.schemas.common import (
    AssetCreateUploadUrl,
    AssetRegisterExternalUrl,
    CaptureUndoRequest,
    LedgerTransactionCreate,
    McpExpenseSummaryRequest,
    McpSearchRequest,
    McpTaskCompleteRequest,
    McpTaskListRequest,
    MemoCreate,
    TaskCreate,
    json_serialize,
)

router = APIRouter()
router.include_router(capture_lifecycle_router)

CLOUD_MCP_SOURCE_CHANNEL = "cloud_mcp"
MCP_AI_ACTOR_TYPE = "ai"
MCP_ENTITY_SOURCE = "ai"
MCP_MAX_CAPTURE_COMMIT_ACTIONS = 10


# ─── Helpers ──────────────────────────────────────────────────────────────────
def _validation_error_detail(exc: ValidationError) -> list[dict]:
    return [
        {
            "loc": list(error.get("loc", [])),
            "msg": error.get("msg", "validation error"),
            "type": error.get("type", "value_error"),
        }
        for error in exc.errors()
    ]


def _request_id(request: Request, body: dict | None = None) -> str | None:
    value = request.headers.get("x-request-id") or (body or {}).get("request_id")
    if value is None:
        return None
    return str(value)[:64]


async def _read_json_body(request: Request) -> dict:
    try:
        body = await request.json()
    except ValueError:
        return {}
    if body is None:
        return {}
    if not isinstance(body, dict):
        raise HTTPException(status_code=422, detail="request body must be a JSON object")
    return body


async def _write_audit(
    db: AsyncSession,
    user_id: str,
    action: str,
    entity_type: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    source: str | None = CLOUD_MCP_SOURCE_CHANNEL,
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
):
    log = AuditLog(
        user_id=user_id,
        actor_type=MCP_AI_ACTOR_TYPE,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
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


async def _persist_create_undo_entries(
    db: AsyncSession,
    *,
    undo_token: str,
    created_entities: list[dict],
) -> None:
    await persist_undo_entries(
        db,
        undo_token=undo_token,
        user_id=DEFAULT_LOCAL_USER_ID,
        entries=[{**entity, "action": "create"} for entity in created_entities],
    )


# ─── capture_parse ────────────────────────────────────────────────────────────
@router.post("/capture/parse")
async def capture_parse(
    data: CaptureParseRequest,
    db: AsyncSession = Depends(get_db),
):
    result = parse_mixed_input(
        data.text,
        timezone_str=data.timezone,
        locale=data.locale,
    )
    result.actions = attach_capture_assets(result.actions, data.asset_ids)
    await persist_capture_session(
        db,
        result=result,
        original_text=data.text,
        timezone_str=data.timezone,
        locale=data.locale,
        user_id=DEFAULT_LOCAL_USER_ID,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
    )
    await persist_capture_turn(
        db,
        capture_id=result.capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        turn_index=0,
        role="user",
        text=data.text,
        asset_ids=data.asset_ids,
        turn_status="accepted",
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
    )
    action_turn = await persist_capture_turn(
        db,
        capture_id=result.capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        turn_index=1,
        role="assistant",
        asset_ids=data.asset_ids,
        actions=result.actions,
        turn_status="parsed",
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
    )
    await db.commit()

    return {
        "capture_id": result.capture_id,
        "turn_id": action_turn.id,
        "actions": [
            {
                "type": action.type,
                "payload": action.payload,
                "confidence": action.confidence,
            }
            for action in result.actions
        ],
        "requires_confirmation": result.requires_confirmation,
    }


# ─── capture_commit ───────────────────────────────────────────────────────────
@router.post("/capture/commit")
async def capture_commit(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = CaptureCommitRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    capture_id = data.capture_id
    selected_indexes = data.selected_action_indexes
    request_id = _request_id(request, body) or data.request_id
    db_session = await get_active_capture_session(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    memory_session = CAPTURE_STORE.get(capture_id)
    if not db_session and not memory_session:
        raise HTTPException(status_code=404, detail="Capture session not found or expired")

    action_turn = None
    if db_session:
        action_turn = (
            await get_capture_turn(
                db,
                capture_id=capture_id,
                turn_id=data.turn_id,
                user_id=DEFAULT_LOCAL_USER_ID,
            )
            if data.turn_id
            else await latest_action_turn(
                db,
                capture_id=capture_id,
                user_id=DEFAULT_LOCAL_USER_ID,
            )
        )
        if action_turn is None or action_turn.role != "assistant":
            raise HTTPException(status_code=404, detail="Capture action turn not found")
        if action_turn.turn_status in {"committed", "partial"}:
            raise HTTPException(status_code=409, detail="Capture turn already committed")
        session_actions = deserialize_capture_actions(action_turn.actions)
    else:
        if memory_session.committed:
            raise HTTPException(status_code=409, detail="Legacy capture action already committed")
        session_actions = memory_session.actions

    selected_count = len(session_actions) if selected_indexes is None else len(selected_indexes)
    if selected_count > MCP_MAX_CAPTURE_COMMIT_ACTIONS:
        raise HTTPException(
            status_code=422,
            detail=f"capture_commit supports at most {MCP_MAX_CAPTURE_COMMIT_ACTIONS} actions per request",
        )

    commit_result = await commit_capture_actions(
        db,
        capture_id=capture_id,
        actions=session_actions,
        selected_indexes=selected_indexes,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        entity_source=MCP_ENTITY_SOURCE,
        source_text=data.source_text,
        request_id=request_id,
    )

    undo_token = str(uuid.uuid4()) if commit_result.created_entities else ""
    if commit_result.created_entities:
        await _persist_create_undo_entries(
            db,
            undo_token=undo_token,
            created_entities=commit_result.created_entities,
        )

    if db_session and action_turn:
        effective_indexes = selected_indexes or list(range(len(session_actions)))
        await mark_capture_turn_committed(
            db,
            turn=action_turn,
            selected_action_indexes=effective_indexes,
            result_entities=commit_result.created_entities,
            undo_token=undo_token,
            has_failures=bool(commit_result.failed_actions),
        )
        if commit_result.created_entities:
            await mark_capture_session_committed(db, db_session)
    if memory_session:
        memory_session.committed = True
    await db.commit()

    return {
        "capture_id": capture_id,
        "turn_id": action_turn.id if action_turn else None,
        "committed": bool(commit_result.created_entities),
        "created_entities": commit_result.created_entities,
        "failed_actions": [failure.to_dict() for failure in commit_result.failed_actions],
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
    request_id = _request_id(request, body)
    entries = await consume_undo_entries(
        db,
        undo_token=undo_token,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if not entries:
        used_entries = await list_undo_entries(
            db,
            undo_token=undo_token,
            user_id=DEFAULT_LOCAL_USER_ID,
            statuses=["used"],
        )
        if used_entries:
            return {"undone": 0, "entities": [], "failed_entities": []}
        raise HTTPException(status_code=404, detail="Undo token not found or expired")

    undone_entities: list[dict] = []
    failed_entities: list[dict] = []

    for entry in entries:
        model_class = {
            "memo": Memo,
            "ledger_transaction": LedgerTransaction,
            "task": Task,
            "asset": Asset,
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
            else _task_dict(entity) if entry.entity_type == "task"
            else asset_to_dict(entity)
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
            request_id=request_id,
        )
        undone_entities.append({"type": entry.entity_type, "id": entry.entity_id})

    committed_turn = await get_turn_by_undo_token(
        db,
        undo_token=undo_token,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    capture_id = committed_turn.capture_id if committed_turn else None
    if committed_turn:
        await mark_capture_turn_undone(db, committed_turn)

    if capture_id is None and undone_entities:
        entity = undone_entities[0]
        model_class = {
            "memo": Memo,
            "ledger_transaction": LedgerTransaction,
            "task": Task,
            "asset": Asset,
        }.get(entity["type"])
        if model_class is not None:
            result = await db.execute(
                select(model_class).where(getattr(model_class, "id") == entity["id"])
            )
            source_entity = result.scalar_one_or_none()
            capture_id = getattr(source_entity, "source_capture_id", None)
    if capture_id:
        turn_index = await next_capture_turn_index(
            db,
            capture_id=capture_id,
            user_id=DEFAULT_LOCAL_USER_ID,
        )
        await persist_capture_turn(
            db,
            capture_id=capture_id,
            user_id=DEFAULT_LOCAL_USER_ID,
            turn_index=turn_index,
            role="system",
            text="undo",
            result_entities=undone_entities,
            undo_token=undo_token,
            turn_status="undone" if not failed_entities else "partial_undo",
            source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        )

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
            "source": body.get("source") or MCP_ENTITY_SOURCE,
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    memo = await create_memo_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="memo_create",
        source_text=body.get("source_text") or body.get("content_markdown"),
        request_id=_request_id(request, body),
    )

    undo_token = str(uuid.uuid4())
    await _persist_create_undo_entries(
        db,
        undo_token=undo_token,
        created_entities=[{"type": "memo", "id": memo.id}],
    )

    await db.commit()
    await db.refresh(memo)

    memo_data = _memo_dict(memo)
    return {
        "memo_id": memo.id,
        "status": memo.status,
        "memo": memo_data,
        "undo_token": undo_token,
    }


@router.post("/memo/search")
async def mcp_memo_search(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = McpSearchRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    query = select(Memo).where(
        Memo.user_id == DEFAULT_LOCAL_USER_ID,
        Memo.status == "active",
    )
    if data.q:
        query = query.where(
            Memo.title.ilike(f"%{data.q}%") | Memo.content_markdown.ilike(f"%{data.q}%")
        )
    query = query.order_by(Memo.created_at.desc()).limit(data.limit)
    result = await db.execute(query)
    return {"memos": [_memo_dict(m) for m in result.scalars().all()]}


@router.post("/expense/create")
async def mcp_expense_create(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    try:
        data = LedgerTransactionCreate.model_validate({
            **body,
            "direction": body.get("direction") or "expense",
            "source": body.get("source") or MCP_ENTITY_SOURCE,
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    tx = await create_ledger_transaction_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="expense_create",
        source_text=body.get("source_text") or body.get("note") or body.get("merchant"),
        request_id=_request_id(request, body),
    )

    undo_token = str(uuid.uuid4())
    await _persist_create_undo_entries(
        db,
        undo_token=undo_token,
        created_entities=[{"type": "ledger_transaction", "id": tx.id}],
    )

    await db.commit()
    await db.refresh(tx)

    return {"transaction": _tx_dict(tx), "undo_token": undo_token}


@router.post("/expense/search")
async def mcp_expense_search(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = McpSearchRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    query = select(LedgerTransaction).where(
        LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        LedgerTransaction.status == "active",
    )
    if data.q:
        query = query.where(
            LedgerTransaction.merchant.ilike(f"%{data.q}%") | LedgerTransaction.note.ilike(f"%{data.q}%")
        )
    query = query.order_by(LedgerTransaction.occurred_at.desc()).limit(data.limit)
    result = await db.execute(query)
    return {"transactions": [_tx_dict(t) for t in result.scalars().all()]}


@router.post("/expense/summary")
async def mcp_expense_summary(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = McpExpenseSummaryRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

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

    return {"period": data.period, "total_expense": total, "count": count}


@router.post("/task/create")
async def mcp_task_create(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    try:
        data = TaskCreate.model_validate({
            **body,
            "source": body.get("source") or MCP_ENTITY_SOURCE,
        })
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    task = await create_task_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="task_create",
        source_text=body.get("source_text") or body.get("title") or body.get("description"),
        request_id=_request_id(request, body),
    )

    undo_token = str(uuid.uuid4())
    await _persist_create_undo_entries(
        db,
        undo_token=undo_token,
        created_entities=[{"type": "task", "id": task.id}],
    )

    await db.commit()
    await db.refresh(task)

    return {"task": _task_dict(task), "undo_token": undo_token}


@router.post("/task/list")
async def mcp_task_list(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = McpTaskListRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    query = select(Task).where(
        Task.user_id == DEFAULT_LOCAL_USER_ID,
        Task.status == "active",
    )
    if data.task_status:
        query = query.where(Task.task_status == data.task_status)
    query = query.order_by(Task.created_at.desc()).limit(data.limit)
    result = await db.execute(query)
    return {"tasks": [_task_dict(t) for t in result.scalars().all()]}


@router.post("/task/complete")
async def mcp_task_complete(request: Request, db: AsyncSession = Depends(get_db)):
    body = await _read_json_body(request)
    try:
        data = McpTaskCompleteRequest.model_validate(body)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    task = await complete_task_record(
        db,
        task_id=data.task_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="task_complete",
        source_text=body.get("source_text") or data.task_id,
        request_id=_request_id(request, body),
    )
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

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
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="asset_create_upload_url",
        source_text=body.get("source_text") or body.get("filename"),
        request_id=_request_id(request, body),
    )
    undo_token = str(uuid.uuid4())
    await _persist_create_undo_entries(
        db,
        undo_token=undo_token,
        created_entities=[{"type": "asset", "id": asset.id}],
    )
    await db.commit()
    await db.refresh(asset)

    return {
        **build_create_upload_url_payload(asset, upload_url),
        "undo_token": undo_token,
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
        actor_type=MCP_AI_ACTOR_TYPE,
        source_channel=CLOUD_MCP_SOURCE_CHANNEL,
        tool_name="asset_register_external_url",
        source_text=body.get("source_text") or body.get("external_url"),
        request_id=_request_id(request, body),
    )
    undo_token = str(uuid.uuid4())
    await _persist_create_undo_entries(
        db,
        undo_token=undo_token,
        created_entities=[{"type": "asset", "id": asset.id}],
    )
    await db.commit()
    await db.refresh(asset)

    return {
        **build_register_external_url_payload(asset),
        "undo_token": undo_token,
    }
