from __future__ import annotations

from datetime import datetime, timedelta, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import McpUndoAction

DEFAULT_UNDO_TTL_HOURS = 24


async def persist_undo_entries(
    db: AsyncSession,
    *,
    undo_token: str,
    user_id: str,
    entries: list[dict],
    ttl_hours: int = DEFAULT_UNDO_TTL_HOURS,
) -> list[McpUndoAction]:
    """Persist a set of undo entries as pending one-shot actions."""

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(hours=ttl_hours)
    rows: list[McpUndoAction] = []

    for entry in entries:
        row = McpUndoAction(
            user_id=user_id,
            undo_token=undo_token,
            entity_type=entry["type"],
            entity_id=entry["id"],
            action=entry.get("action") or "create",
            status="pending",
            expires_at=expires_at,
        )
        db.add(row)
        rows.append(row)

    await db.flush()
    return rows


async def consume_undo_entries(
    db: AsyncSession,
    *,
    undo_token: str,
    user_id: str,
) -> list[McpUndoAction]:
    """Return pending undo entries and mark them used in the current transaction."""

    now = datetime.now(timezone.utc)
    result = await db.execute(
        select(McpUndoAction)
        .where(
            McpUndoAction.user_id == user_id,
            McpUndoAction.undo_token == undo_token,
            McpUndoAction.status == "pending",
            or_(McpUndoAction.expires_at.is_(None), McpUndoAction.expires_at > now),
        )
        .order_by(McpUndoAction.created_at.asc())
    )
    rows = list(result.scalars().all())

    for row in rows:
        row.status = "used"
        row.used_at = now

    await db.flush()
    return rows
