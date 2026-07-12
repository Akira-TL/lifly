from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditLog, LedgerBudget, LedgerTransaction
from app.schemas.common import (
    LedgerBudgetResponse,
    LedgerTransactionCreate,
    LedgerTransactionResponse,
    json_serialize,
)

DEFAULT_LOCAL_USER_ID = "local-dev"


def ledger_transaction_to_response(tx: LedgerTransaction) -> LedgerTransactionResponse:
    return LedgerTransactionResponse(
        id=tx.id,
        user_id=tx.user_id,
        direction=tx.direction,
        amount=float(tx.amount),
        currency=tx.currency,
        account_id=tx.account_id,
        category_id=tx.category_id,
        merchant=tx.merchant,
        note=tx.note,
        occurred_at=tx.occurred_at,
        source=tx.source,
        confidence=float(tx.confidence) if tx.confidence is not None else None,
        status=tx.status,
        created_at=tx.created_at,
        updated_at=tx.updated_at,
    )


def ledger_transaction_to_dict(tx: LedgerTransaction) -> dict:
    return json_serialize(ledger_transaction_to_response(tx).model_dump())


def ledger_budget_to_response(
    budget: LedgerBudget,
    *,
    category_name: str | None = None,
) -> LedgerBudgetResponse:
    return LedgerBudgetResponse(
        id=budget.id,
        user_id=budget.user_id,
        period_type=budget.period_type,
        period_key=budget.period_key,
        category_id=budget.category_id,
        category_name=category_name,
        amount=float(budget.amount),
        currency=budget.currency,
        alert_threshold=(
            float(budget.alert_threshold) if budget.alert_threshold is not None else None
        ),
        status=budget.status,
        revision=budget.revision,
        created_at=budget.created_at,
        updated_at=budget.updated_at,
    )


def ledger_budget_to_dict(
    budget: LedgerBudget,
    *,
    category_name: str | None = None,
) -> dict:
    return json_serialize(
        ledger_budget_to_response(budget, category_name=category_name).model_dump()
    )


async def write_ledger_audit(
    db: AsyncSession,
    *,
    user_id: str,
    action: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
    entity_type: str = "ledger_transaction",
) -> AuditLog:
    log = AuditLog(
        user_id=user_id,
        actor_type=actor_type,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
    )
    db.add(log)
    return log


async def create_ledger_transaction_record(
    db: AsyncSession,
    data: LedgerTransactionCreate,
    *,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> LedgerTransaction:
    tx = LedgerTransaction(
        user_id=user_id,
        direction=data.direction,
        amount=data.amount,
        currency=data.currency,
        account_id=data.account_id,
        category_id=data.category_id,
        merchant=data.merchant,
        note=data.note,
        occurred_at=data.occurred_at or datetime.now(timezone.utc),
        source=data.source,
        source_capture_id=data.source_capture_id,
        confidence=data.confidence,
    )
    db.add(tx)
    await db.flush()

    await write_ledger_audit(
        db,
        user_id=user_id,
        action="create",
        entity_id=tx.id,
        after=ledger_transaction_to_dict(tx),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
    )
    return tx
