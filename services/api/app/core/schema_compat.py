from __future__ import annotations

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


async def ensure_schema_compatibility(conn: AsyncConnection) -> None:
    """Apply additive compatibility changes until a full migration runner lands."""
    dialect = conn.dialect.name
    if dialect == "postgresql":
        await conn.execute(
            text(
                "ALTER TABLE ledger_budgets "
                "ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1"
            )
        )
        reminder_columns = (
            "ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()",
            "ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1",
            "ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0",
            "ADD COLUMN IF NOT EXISTS max_attempts INTEGER NOT NULL DEFAULT 3",
            "ADD COLUMN IF NOT EXISTS next_attempt_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS last_attempt_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS last_error TEXT",
            "ADD COLUMN IF NOT EXISTS external_id VARCHAR(256)",
            "ADD COLUMN IF NOT EXISTS dispatch_token VARCHAR(64)",
            "ADD COLUMN IF NOT EXISTS lease_until TIMESTAMPTZ",
        )
        for definition in reminder_columns:
            await conn.execute(text(f"ALTER TABLE reminders {definition}"))
        await conn.execute(
            text(
                "UPDATE reminders SET next_attempt_at = remind_at "
                "WHERE next_attempt_at IS NULL AND reminder_status = 'pending'"
            )
        )
        capture_session_columns = (
            "ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1",
            "ADD COLUMN IF NOT EXISTS session_status VARCHAR(20)",
            "ADD COLUMN IF NOT EXISTS committed_at TIMESTAMPTZ",
            "ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ",
        )
        for definition in capture_session_columns:
            await conn.execute(text(f"ALTER TABLE mcp_capture_sessions {definition}"))
        await conn.execute(
            text(
                "UPDATE mcp_capture_sessions "
                "SET session_status = CASE WHEN committed THEN 'committed' ELSE 'active' END "
                "WHERE session_status IS NULL"
            )
        )
        await conn.execute(
            text(
                "UPDATE mcp_capture_sessions SET committed_at = updated_at "
                "WHERE committed IS TRUE AND committed_at IS NULL"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE mcp_capture_sessions "
                "ALTER COLUMN session_status SET DEFAULT 'active'"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE mcp_capture_sessions "
                "ALTER COLUMN session_status SET NOT NULL"
            )
        )
        await conn.execute(
            text(
                "ALTER TABLE encrypted_entities "
                "ALTER COLUMN id TYPE VARCHAR(128)"
            )
        )
        capture_turn_columns = (
            "ADD COLUMN IF NOT EXISTS revision INTEGER NOT NULL DEFAULT 1",
            "ADD COLUMN IF NOT EXISTS asset_ids JSONB",
            "ADD COLUMN IF NOT EXISTS asset_context JSONB",
            "ADD COLUMN IF NOT EXISTS undo_token VARCHAR(36)",
            "ADD COLUMN IF NOT EXISTS supersedes_turn_id VARCHAR(36)",
        )
        for definition in capture_turn_columns:
            await conn.execute(text(f"ALTER TABLE mcp_capture_turns {definition}"))
        await _ensure_powersync_publication(conn)
        return

    if dialect == "sqlite":
        await _add_sqlite_columns(
            conn,
            "ledger_budgets",
            {"revision": "INTEGER NOT NULL DEFAULT 1"},
        )
        await _add_sqlite_columns(
            conn,
            "reminders",
            {
                "updated_at": "TEXT",
                "revision": "INTEGER NOT NULL DEFAULT 1",
                "attempt_count": "INTEGER NOT NULL DEFAULT 0",
                "max_attempts": "INTEGER NOT NULL DEFAULT 3",
                "next_attempt_at": "TEXT",
                "last_attempt_at": "TEXT",
                "delivered_at": "TEXT",
                "failed_at": "TEXT",
                "cancelled_at": "TEXT",
                "last_error": "TEXT",
                "external_id": "TEXT",
                "dispatch_token": "TEXT",
                "lease_until": "TEXT",
            },
        )
        await conn.execute(
            text(
                "UPDATE reminders SET updated_at = created_at "
                "WHERE updated_at IS NULL"
            )
        )
        await conn.execute(
            text(
                "UPDATE reminders SET next_attempt_at = remind_at "
                "WHERE next_attempt_at IS NULL AND reminder_status = 'pending'"
            )
        )
        await _add_sqlite_columns(
            conn,
            "mcp_capture_sessions",
            {
                "revision": "INTEGER NOT NULL DEFAULT 1",
                "session_status": "TEXT NOT NULL DEFAULT 'active'",
                "committed_at": "TEXT",
                "dismissed_at": "TEXT",
            },
        )
        await conn.execute(
            text(
                "UPDATE mcp_capture_sessions "
                "SET session_status = CASE WHEN committed THEN 'committed' ELSE 'active' END "
                "WHERE session_status IS NULL OR session_status = ''"
            )
        )
        await _add_sqlite_columns(
            conn,
            "mcp_capture_turns",
            {
                "revision": "INTEGER NOT NULL DEFAULT 1",
                "asset_ids": "TEXT",
                "asset_context": "TEXT",
                "undo_token": "TEXT",
                "supersedes_turn_id": "TEXT",
            },
        )


async def _ensure_powersync_publication(conn: AsyncConnection) -> None:
    publication = await conn.execute(
        text("SELECT puballtables FROM pg_publication WHERE pubname = 'powersync'")
    )
    all_tables = publication.scalar_one_or_none()
    if all_tables is None:
        await conn.execute(
            text("CREATE PUBLICATION powersync FOR TABLE public.encrypted_entities")
        )
        return
    if bool(all_tables):
        # A FOR ALL TABLES publication cannot be converted with ALTER ... SET
        # TABLE. Recreate it transactionally under the same stable name.
        await conn.execute(text("DROP PUBLICATION powersync"))
        await conn.execute(
            text("CREATE PUBLICATION powersync FOR TABLE public.encrypted_entities")
        )
        return
    await conn.execute(
        text("ALTER PUBLICATION powersync SET TABLE public.encrypted_entities")
    )


async def _add_sqlite_columns(
    conn: AsyncConnection,
    table: str,
    columns: dict[str, str],
) -> None:
    result = await conn.execute(text(f"PRAGMA table_info({table})"))
    existing = {str(row[1]) for row in result.fetchall()}
    for name, definition in columns.items():
        if name not in existing:
            await conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {name} {definition}"))
