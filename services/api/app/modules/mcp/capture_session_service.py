from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import McpCaptureSession, McpCaptureTurn
from app.modules.mcp.parse_engine import CandidateAction, ParseResult

CAPTURE_SESSION_TTL = timedelta(hours=1)


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


def deserialize_capture_actions(actions: list[dict]) -> list[CandidateAction]:
    return [
        CandidateAction(
            type=str(action.get("type") or "memo_create"),
            payload=dict(action.get("payload") or {}),
            confidence=float(action.get("confidence") or 0),
            raw_text=str(action.get("raw_text") or ""),
        )
        for action in actions
    ]


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
        session_status="parsed",
        source_channel=source_channel,
        expires_at=_now() + CAPTURE_SESSION_TTL,
    )
    db.add(session)
    await db.flush()
    return session


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
            McpCaptureSession.expires_at > _now(),
        )
    )
    return result.scalar_one_or_none()


async def persist_capture_turn(
    db: AsyncSession,
    *,
    capture_id: str,
    user_id: str,
    turn_index: int,
    role: str,
    text: str | None = None,
    actions: list[CandidateAction] | None = None,
    selected_action_indexes: list[int] | None = None,
    result_entities: list[dict] | None = None,
    turn_status: str = "parsed",
    source_channel: str,
) -> McpCaptureTurn:
    turn = McpCaptureTurn(
        user_id=user_id,
        capture_id=capture_id,
        turn_index=turn_index,
        role=role,
        text=text,
        actions=serialize_capture_actions(actions or []),
        selected_action_indexes=selected_action_indexes or [],
        result_entities=result_entities or [],
        turn_status=turn_status,
        source_channel=source_channel,
    )
    db.add(turn)
    await db.flush()
    return turn


async def mark_capture_session_committed(db: AsyncSession, session: McpCaptureSession) -> None:
    session.committed = True
    session.session_status = "committed"
    session.committed_at = _now()
    await db.flush()
