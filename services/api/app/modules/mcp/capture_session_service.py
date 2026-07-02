from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import McpCaptureSession
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


async def mark_capture_session_committed(db: AsyncSession, session: McpCaptureSession) -> None:
    session.committed = True
    await db.flush()
