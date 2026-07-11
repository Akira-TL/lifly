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
        return

    if dialect == "sqlite":
        result = await conn.execute(text("PRAGMA table_info(ledger_budgets)"))
        columns = {str(row[1]) for row in result.fetchall()}
        if "revision" not in columns:
            await conn.execute(
                text(
                    "ALTER TABLE ledger_budgets "
                    "ADD COLUMN revision INTEGER NOT NULL DEFAULT 1"
                )
            )
