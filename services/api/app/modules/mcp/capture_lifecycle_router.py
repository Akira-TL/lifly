from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.mcp.capture_asset_context import (
    build_capture_parse_text,
    resolve_capture_asset_contexts,
)
from app.modules.mcp.capture_schemas import (
    CaptureAppendTurnRequest,
    CaptureDismissRequest,
    CaptureReviseActionRequest,
)
from app.modules.mcp.capture_session_service import (
    capture_session_summary_data,
    capture_turn_data,
    deserialize_capture_actions,
    dismiss_capture_session,
    get_active_capture_session,
    get_capture_session,
    get_capture_turn,
    list_capture_sessions,
    list_capture_turns,
    next_capture_turn_index,
    persist_capture_turn,
    revise_capture_actions,
    update_capture_session_actions,
)
from app.modules.mcp.parse_engine import CandidateAction, parse_mixed_input
from app.modules.memos.service import DEFAULT_LOCAL_USER_ID

router = APIRouter(prefix="/capture")
SOURCE_CHANNEL = "cloud_mcp"


def attach_capture_assets(
    actions: list[CandidateAction],
    asset_ids: list[str],
) -> list[CandidateAction]:
    if not asset_ids:
        return actions
    enriched: list[CandidateAction] = []
    for action in actions:
        payload = dict(action.payload)
        if action.type == "memo_create":
            payload["asset_ids"] = asset_ids
        enriched.append(
            CandidateAction(
                type=action.type,
                payload=payload,
                confidence=action.confidence,
                raw_text=action.raw_text,
            )
        )
    return enriched


async def _session_detail(db: AsyncSession, capture_id: str) -> dict:
    session = await get_capture_session(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Capture session not found")
    turns = await list_capture_turns(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    return {
        **capture_session_summary_data(session, turn_count=len(turns)),
        "turns": [capture_turn_data(turn) for turn in turns],
    }


@router.get("/sessions")
async def capture_session_list(
    status: str | None = Query(default="active"),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    sessions, total = await list_capture_sessions(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        status=status,
        limit=limit,
        offset=offset,
    )
    items: list[dict] = []
    for session in sessions:
        turns = await list_capture_turns(
            db,
            capture_id=session.capture_id,
            user_id=DEFAULT_LOCAL_USER_ID,
        )
        items.append(capture_session_summary_data(session, turn_count=len(turns)))
    return {
        "total": total,
        "limit": limit,
        "offset": offset,
        "items": items,
    }


@router.get("/sessions/{capture_id}")
async def capture_session_get(
    capture_id: str,
    db: AsyncSession = Depends(get_db),
):
    return await _session_detail(db, capture_id)


@router.post("/sessions/{capture_id}/turns")
async def capture_session_append_turn(
    capture_id: str,
    data: CaptureAppendTurnRequest,
    db: AsyncSession = Depends(get_db),
):
    session = await get_active_capture_session(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Capture session not found, dismissed, or expired")

    asset_context = await resolve_capture_asset_contexts(
        db,
        asset_ids=data.asset_ids,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    serialized_context = [
        item.model_dump(mode="json") for item in asset_context.contexts
    ]
    next_index = await next_capture_turn_index(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    await persist_capture_turn(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        turn_index=next_index,
        role="user",
        text=data.text,
        asset_ids=data.asset_ids,
        asset_context=serialized_context,
        turn_status="accepted",
        source_channel=SOURCE_CHANNEL,
    )

    parsed = parse_mixed_input(
        build_capture_parse_text(data.text, asset_context),
        timezone_str=session.timezone,
        locale=session.locale,
    )
    actions = attach_capture_assets(parsed.actions, data.asset_ids)
    await persist_capture_turn(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        turn_index=next_index + 1,
        role="assistant",
        text=None,
        asset_ids=data.asset_ids,
        asset_context=serialized_context,
        actions=actions,
        turn_status="parsed",
        source_channel=SOURCE_CHANNEL,
    )
    await update_capture_session_actions(
        db,
        session=session,
        actions=actions,
        requires_confirmation=parsed.requires_confirmation,
    )
    await db.commit()
    return await _session_detail(db, capture_id)


@router.post("/sessions/{capture_id}/turns/{turn_id}/revise")
async def capture_session_revise_action(
    capture_id: str,
    turn_id: str,
    data: CaptureReviseActionRequest,
    db: AsyncSession = Depends(get_db),
):
    session = await get_active_capture_session(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Capture session not found, dismissed, or expired")
    source_turn = await get_capture_turn(
        db,
        capture_id=capture_id,
        turn_id=turn_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if source_turn is None or source_turn.role != "assistant":
        raise HTTPException(status_code=404, detail="Capture action turn not found")
    if source_turn.turn_status in {"committed", "partial"}:
        raise HTTPException(
            status_code=409,
            detail="Undo the committed turn before revising it",
        )

    try:
        actions = revise_capture_actions(
            source_actions=deserialize_capture_actions(source_turn.actions),
            action_index=data.action_index,
            action_type=data.action_type,
            payload=dict(data.payload),
            confidence=data.confidence,
        )
    except IndexError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    next_index = await next_capture_turn_index(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    revised_turn = await persist_capture_turn(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        turn_index=next_index,
        role="assistant",
        text=data.note,
        asset_ids=list(source_turn.asset_ids or []),
        asset_context=list(source_turn.asset_context or []),
        actions=actions,
        supersedes_turn_id=source_turn.id,
        turn_status="revised",
        source_channel=SOURCE_CHANNEL,
    )
    source_turn.turn_status = "superseded"
    source_turn.revision += 1
    await update_capture_session_actions(
        db,
        session=session,
        actions=actions,
        requires_confirmation=True,
    )
    await db.commit()
    return {
        "capture_id": capture_id,
        "turn": capture_turn_data(revised_turn),
    }


@router.post("/sessions/{capture_id}/dismiss")
async def capture_session_dismiss(
    capture_id: str,
    data: CaptureDismissRequest,
    db: AsyncSession = Depends(get_db),
):
    session = await get_capture_session(
        db,
        capture_id=capture_id,
        user_id=DEFAULT_LOCAL_USER_ID,
    )
    if session is None:
        raise HTTPException(status_code=404, detail="Capture session not found")
    if session.session_status != "dismissed":
        next_index = await next_capture_turn_index(
            db,
            capture_id=capture_id,
            user_id=DEFAULT_LOCAL_USER_ID,
        )
        await persist_capture_turn(
            db,
            capture_id=capture_id,
            user_id=DEFAULT_LOCAL_USER_ID,
            turn_index=next_index,
            role="system",
            text=data.reason or "dismiss",
            turn_status="dismissed",
            source_channel=SOURCE_CHANNEL,
        )
        await dismiss_capture_session(db, session=session)
        await db.commit()
    return await _session_detail(db, capture_id)
