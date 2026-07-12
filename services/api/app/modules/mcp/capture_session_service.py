from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import McpCaptureSession, McpCaptureTurn
from app.modules.mcp.parse_engine import CandidateAction, ParseResult

CAPTURE_SESSION_TTL = timedelta(days=30)
ACTIVE_CAPTURE_STATUSES = ("active", "parsed", "committed", "failed")
ACTION_TURN_STATUSES = ("parsed", "revised", "failed")


def _now() -> datetime:
    return datetime.now(timezone.utc)


def serialize_capture_actions(actions: list[CandidateAction]) -> list[dict]:
    return [
        {
            "type": action.type,
            "payload": action.payload,
            "confidence": action.confidence,
            "raw_text": action.raw_text,
        }
        for action in actions
    ]


def deserialize_capture_actions(actions: list[dict] | None) -> list[CandidateAction]:
    return [
        CandidateAction(
            type=str(action.get("type") or "memo_create"),
            payload=dict(action.get("payload") or {}),
            confidence=float(action.get("confidence") or 0),
            raw_text=str(action.get("raw_text") or ""),
        )
        for action in (actions or [])
    ]


def capture_turn_data(turn: McpCaptureTurn) -> dict:
    return {
        "id": turn.id,
        "capture_id": turn.capture_id,
        "turn_index": turn.turn_index,
        "role": turn.role,
        "text": turn.text,
        "asset_ids": list(turn.asset_ids or []),
        "asset_context": list(turn.asset_context or []),
        "actions": list(turn.actions or []),
        "selected_action_indexes": list(turn.selected_action_indexes or []),
        "result_entities": list(turn.result_entities or []),
        "undo_token": turn.undo_token,
        "supersedes_turn_id": turn.supersedes_turn_id,
        "turn_status": turn.turn_status,
        "source_channel": turn.source_channel,
        "created_at": turn.created_at.isoformat() if turn.created_at else None,
        "updated_at": turn.updated_at.isoformat() if turn.updated_at else None,
    }


def capture_session_summary_data(session: McpCaptureSession, *, turn_count: int = 0) -> dict:
    return {
        "capture_id": session.capture_id,
        "original_text": session.original_text,
        "timezone": session.timezone,
        "locale": session.locale,
        "actions": list(session.actions or []),
        "requires_confirmation": session.requires_confirmation,
        "committed": session.committed,
        "session_status": session.session_status,
        "source_channel": session.source_channel,
        "expires_at": session.expires_at.isoformat() if session.expires_at else None,
        "committed_at": session.committed_at.isoformat() if session.committed_at else None,
        "dismissed_at": session.dismissed_at.isoformat() if session.dismissed_at else None,
        "created_at": session.created_at.isoformat() if session.created_at else None,
        "updated_at": session.updated_at.isoformat() if session.updated_at else None,
        "turn_count": turn_count,
    }


async def persist_capture_session(
    db: AsyncSession,
    *,
    result: ParseResult,
    original_text: str,
    timezone_str: str,
    locale: str,
    user_id: str,
    source_channel: str,
) -> McpCaptureSession:
    session = McpCaptureSession(
        capture_id=result.capture_id,
        user_id=user_id,
        original_text=original_text,
        timezone=timezone_str,
        locale=locale,
        actions=serialize_capture_actions(result.actions),
        requires_confirmation=result.requires_confirmation,
        committed=False,
        session_status="active",
        source_channel=source_channel,
        expires_at=_now() + CAPTURE_SESSION_TTL,
    )
    db.add(session)
    await db.flush()
    return session


async def get_capture_session(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
) -> McpCaptureSession | None:
    result = await db.execute(
        select(McpCaptureSession).where(
            McpCaptureSession.capture_id == capture_id,
            McpCaptureSession.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


async def get_active_capture_session(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
) -> McpCaptureSession | None:
    result = await db.execute(
        select(McpCaptureSession).where(
            McpCaptureSession.capture_id == capture_id,
            McpCaptureSession.user_id == user_id,
            McpCaptureSession.session_status.in_(ACTIVE_CAPTURE_STATUSES),
            McpCaptureSession.expires_at > _now(),
        )
    )
    return result.scalar_one_or_none()


async def list_capture_sessions(
    db: AsyncSession,
    *,
    user_id: str,
    status: str | None,
    limit: int,
    offset: int,
) -> tuple[list[McpCaptureSession], int]:
    query = select(McpCaptureSession).where(McpCaptureSession.user_id == user_id)
    if status == "active":
        query = query.where(McpCaptureSession.session_status.in_(ACTIVE_CAPTURE_STATUSES))
    elif status:
        query = query.where(McpCaptureSession.session_status == status)
    count = await db.scalar(select(func.count()).select_from(query.subquery()))
    result = await db.execute(
        query.order_by(McpCaptureSession.updated_at.desc()).limit(limit).offset(offset)
    )
    return list(result.scalars().all()), int(count or 0)


async def list_capture_turns(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
) -> list[McpCaptureTurn]:
    result = await db.execute(
        select(McpCaptureTurn)
        .where(
            McpCaptureTurn.capture_id == capture_id,
            McpCaptureTurn.user_id == user_id,
        )
        .order_by(McpCaptureTurn.turn_index.asc(), McpCaptureTurn.created_at.asc())
    )
    return list(result.scalars().all())


async def get_capture_turn(
    db: AsyncSession,
    *,
    capture_id: str,
    turn_id: str,
    user_id: str,
) -> McpCaptureTurn | None:
    result = await db.execute(
        select(McpCaptureTurn).where(
            McpCaptureTurn.id == turn_id,
            McpCaptureTurn.capture_id == capture_id,
            McpCaptureTurn.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


async def get_turn_by_undo_token(
    db: AsyncSession,
    *,
    undo_token: str,
    user_id: str,
) -> McpCaptureTurn | None:
    result = await db.execute(
        select(McpCaptureTurn).where(
            McpCaptureTurn.undo_token == undo_token,
            McpCaptureTurn.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


async def latest_action_turn(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
) -> McpCaptureTurn | None:
    result = await db.execute(
        select(McpCaptureTurn)
        .where(
            McpCaptureTurn.capture_id == capture_id,
            McpCaptureTurn.user_id == user_id,
            McpCaptureTurn.role == "assistant",
            McpCaptureTurn.turn_status.in_(ACTION_TURN_STATUSES),
        )
        .order_by(McpCaptureTurn.turn_index.desc(), McpCaptureTurn.created_at.desc())
    )
    return result.scalars().first()


async def next_capture_turn_index(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
) -> int:
    value = await db.scalar(
        select(func.max(McpCaptureTurn.turn_index)).where(
            McpCaptureTurn.capture_id == capture_id,
            McpCaptureTurn.user_id == user_id,
        )
    )
    return int(value if value is not None else -1) + 1


async def persist_capture_turn(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
    turn_index: int,
    role: str,
    text: str | None = None,
    asset_ids: list[str] | None = None,
    asset_context: list[dict] | None = None,
    actions: list[CandidateAction] | None = None,
    selected_action_indexes: list[int] | None = None,
    result_entities: list[dict] | None = None,
    undo_token: str | None = None,
    supersedes_turn_id: str | None = None,
    turn_status: str = "parsed",
    source_channel: str,
) -> McpCaptureTurn:
    turn = McpCaptureTurn(
        user_id=user_id,
        capture_id=capture_id,
        turn_index=turn_index,
        role=role,
        text=text,
        asset_ids=asset_ids or [],
        asset_context=asset_context or [],
        actions=serialize_capture_actions(actions or []),
        selected_action_indexes=selected_action_indexes or [],
        result_entities=result_entities or [],
        undo_token=undo_token,
        supersedes_turn_id=supersedes_turn_id,
        turn_status=turn_status,
        source_channel=source_channel,
    )
    db.add(turn)
    await db.flush()
    return turn


async def update_capture_session_actions(
    db: AsyncSession,
    *,
    session: McpCaptureSession,
    actions: list[CandidateAction],
    requires_confirmation: bool,
) -> None:
    session.actions = serialize_capture_actions(actions)
    session.requires_confirmation = requires_confirmation
    session.session_status = "active"
    session.expires_at = _now() + CAPTURE_SESSION_TTL
    session.revision += 1
    await db.flush()


async def mark_capture_session_committed(db: AsyncSession, session: McpCaptureSession) -> None:
    session.committed = True
    session.session_status = "active"
    session.committed_at = _now()
    session.expires_at = _now() + CAPTURE_SESSION_TTL
    session.revision += 1
    await db.flush()


async def mark_capture_turn_committed(
    db: AsyncSession,
    *,
    turn: McpCaptureTurn,
    selected_action_indexes: list[int],
    result_entities: list[dict],
    undo_token: str,
    has_failures: bool,
) -> None:
    turn.selected_action_indexes = selected_action_indexes
    turn.result_entities = result_entities
    turn.undo_token = undo_token
    if not result_entities:
        turn.turn_status = "failed"
    elif has_failures:
        turn.turn_status = "partial"
    else:
        turn.turn_status = "committed"
    turn.revision += 1
    await db.flush()


async def mark_capture_turn_undone(db: AsyncSession, turn: McpCaptureTurn) -> None:
    turn.turn_status = "undone"
    turn.revision += 1
    await db.flush()


async def dismiss_capture_session(
    db: AsyncSession,
    *,
    session: McpCaptureSession,
) -> None:
    session.session_status = "dismissed"
    session.dismissed_at = _now()
    session.revision += 1
    await db.flush()


def revise_capture_actions(
    *,
    source_actions: list[CandidateAction],
    action_index: int,
    action_type: str | None,
    payload: dict,
    confidence: float | None,
) -> list[CandidateAction]:
    if action_index < 0 or action_index >= len(source_actions):
        raise IndexError("action_index_out_of_range")
    revised = list(source_actions)
    source = source_actions[action_index]
    revised[action_index] = CandidateAction(
        type=action_type or source.type,
        payload=dict(payload),
        confidence=source.confidence if confidence is None else confidence,
        raw_text=source.raw_text,
    )
    return revised
