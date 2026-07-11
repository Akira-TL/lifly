from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import create_access_token
from app.db.models import (
    AuditLog,
    LedgerBudget,
    LedgerCategory,
    LedgerTransaction,
    Memo,
    Task,
)
from app.modules.ledger.service import ledger_budget_to_dict, ledger_transaction_to_dict
from app.modules.memos.service import memo_to_response
from app.modules.sync.schemas import (
    PowerSyncCredentialsResponse,
    SyncApplyResult,
    SyncChange,
    SyncPushRequest,
    SyncPushResponse,
)
from app.modules.tasks.service import task_to_dict
from app.schemas.common import json_serialize


def issue_powersync_credentials() -> PowerSyncCredentialsResponse:
    expires_at = datetime.now(timezone.utc) + timedelta(
        minutes=settings.powersync_token_expire_minutes
    )
    token = create_access_token(
        settings.powersync_dev_user_id,
        expires_delta=timedelta(minutes=settings.powersync_token_expire_minutes),
    )
    return PowerSyncCredentialsResponse(
        endpoint=settings.powersync_url,
        token=token,
        user_id=settings.powersync_dev_user_id,
        expires_at=expires_at,
    )


async def apply_sync_push(db: AsyncSession, request: SyncPushRequest) -> SyncPushResponse:
    results: list[SyncApplyResult] = []
    for change in request.changes:
        if change.entity_type == "memo":
            result = await _apply_memo_change(db, change, request.client_id)
        elif change.entity_type == "task":
            result = await _apply_task_change(db, change, request.client_id)
        elif change.entity_type == "ledger_budget":
            result = await _apply_budget_change(db, change, request.client_id)
        else:
            result = await _apply_expense_change(db, change, request.client_id)
        results.append(result)

    applied = sum(1 for item in results if item.status == "applied")
    skipped = len(results) - applied
    return SyncPushResponse(applied=applied, skipped=skipped, results=results)


async def _apply_memo_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    memo = await _find_entity(db, Memo, change)
    if _is_stale(memo, change):
        return _skipped(change, "stale_revision", memo.revision)

    if change.operation == "delete":
        if memo is None:
            return _skipped(change, "missing_entity", None)
        before = _memo_snapshot(memo)
        memo.status = change.data.get("status") or "deleted"
        memo.deleted_at = change.deleted_at
        memo.updated_at = change.updated_at
        memo.revision = change.revision
        await db.flush()
        await _write_sync_audit(db, change, client_id, before=before, after=_memo_snapshot(memo))
        return _applied(change)

    if memo is None:
        memo = Memo(id=change.entity_id, user_id=change.user_id)
        db.add(memo)

    before = _memo_snapshot(memo) if memo.created_at is not None else None
    data = change.data
    memo.type = data.get("type") or memo.type or "memo"
    memo.title = data.get("title")
    memo.content_markdown = data.get("content_markdown") or ""
    memo.tags = data.get("tags")
    memo.mood = data.get("mood")
    memo.source_capture_id = data.get("source_capture_id")
    memo.status = data.get("status") or "active"
    memo.source = data.get("source") or change.source
    memo.revision = change.revision
    if memo.created_at is None:
        memo.created_at = change.created_at or change.updated_at
    memo.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(db, change, client_id, before=before, after=_memo_snapshot(memo))
    return _applied(change)


async def _apply_task_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    task = await _find_entity(db, Task, change)
    if _is_stale(task, change):
        return _skipped(change, "stale_revision", task.revision)

    if change.operation == "delete":
        if task is None:
            return _skipped(change, "missing_entity", None)
        before = task_to_dict(task)
        task.status = change.data.get("status") or "deleted"
        task.deleted_at = change.deleted_at
        task.updated_at = change.updated_at
        task.revision = change.revision
        await db.flush()
        await _write_sync_audit(db, change, client_id, before=before, after=task_to_dict(task))
        return _applied(change)

    if task is None:
        task = Task(id=change.entity_id, user_id=change.user_id, title="")
        db.add(task)

    before = task_to_dict(task) if task.created_at is not None else None
    data = change.data
    task.title = data.get("title") or task.title
    task.description = data.get("description")
    task.due_at = _datetime_value(data.get("due_at"))
    task.remind_at = _datetime_value(data.get("remind_at"))
    task.priority = data.get("priority") or "normal"
    task.task_status = data.get("task_status") or "todo"
    task.completed_at = _datetime_value(data.get("completed_at"))
    task.source_capture_id = data.get("source_capture_id")
    task.status = data.get("status") or "active"
    task.source = data.get("source") or change.source
    task.revision = change.revision
    if task.created_at is None:
        task.created_at = change.created_at or change.updated_at
    task.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(db, change, client_id, before=before, after=task_to_dict(task))
    return _applied(change)


async def _apply_budget_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    budget = await _find_entity(db, LedgerBudget, change)
    if _is_stale(budget, change):
        return _skipped(change, "stale_revision", budget.revision)

    if change.operation == "delete":
        if budget is None:
            return _skipped(change, "missing_entity", None)
        before = ledger_budget_to_dict(budget)
        budget.status = change.data.get("status") or "deleted"
        budget.updated_at = change.updated_at
        budget.revision = change.revision
        await db.flush()
        await _write_sync_audit(
            db,
            change,
            client_id,
            before=before,
            after=ledger_budget_to_dict(budget),
        )
        return _applied(change)

    data = change.data
    amount = data.get("amount")
    period_type = data.get("period_type") or "month"
    period_key = data.get("period_key")
    category_id = data.get("category_id")
    status = data.get("status") or "active"
    threshold = data.get("alert_threshold")
    if amount is None or float(amount) <= 0:
        return _skipped(
            change,
            "invalid_amount",
            budget.revision if budget is not None else None,
        )
    if period_type != "month" or not _valid_month_period(period_key):
        return _skipped(
            change,
            "invalid_period",
            budget.revision if budget is not None else None,
        )
    if status not in {"active", "deleted"}:
        return _skipped(
            change,
            "invalid_status",
            budget.revision if budget is not None else None,
        )
    if threshold is not None and not 0 < float(threshold) <= 1:
        return _skipped(
            change,
            "invalid_alert_threshold",
            budget.revision if budget is not None else None,
        )
    if category_id is not None:
        category = await db.scalar(
            select(LedgerCategory).where(
                LedgerCategory.id == category_id,
                LedgerCategory.user_id == change.user_id,
                LedgerCategory.status == "active",
            )
        )
        if category is None:
            return _skipped(
                change,
                "missing_budget_category",
                budget.revision if budget is not None else None,
            )
        if category.type != "expense":
            return _skipped(
                change,
                "invalid_budget_category_type",
                budget.revision if budget is not None else None,
            )

    conflict_query = select(LedgerBudget).where(
        LedgerBudget.user_id == change.user_id,
        LedgerBudget.status == "active",
        LedgerBudget.period_type == period_type,
        LedgerBudget.period_key == period_key,
        LedgerBudget.id != change.entity_id,
    )
    conflict_query = conflict_query.where(
        LedgerBudget.category_id.is_(None)
        if category_id is None
        else LedgerBudget.category_id == category_id
    )
    if status == "active" and await db.scalar(conflict_query) is not None:
        return _skipped(
            change,
            "duplicate_budget",
            budget.revision if budget is not None else None,
        )

    if budget is None:
        budget = LedgerBudget(id=change.entity_id, user_id=change.user_id)
        db.add(budget)
    before = ledger_budget_to_dict(budget) if budget.created_at is not None else None
    budget.period_type = period_type
    budget.period_key = period_key
    budget.category_id = category_id
    budget.amount = float(amount)
    budget.currency = (data.get("currency") or "CNY").upper()
    budget.alert_threshold = threshold
    budget.status = status
    budget.revision = change.revision
    if budget.created_at is None:
        budget.created_at = change.created_at or change.updated_at
    budget.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(
        db,
        change,
        client_id,
        before=before,
        after=ledger_budget_to_dict(budget),
    )
    return _applied(change)


async def _apply_expense_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    tx = await _find_entity(db, LedgerTransaction, change)
    if _is_stale(tx, change):
        return _skipped(change, "stale_revision", tx.revision)

    if change.operation == "delete":
        if tx is None:
            return _skipped(change, "missing_entity", None)
        before = ledger_transaction_to_dict(tx)
        tx.status = change.data.get("status") or "deleted"
        tx.deleted_at = change.deleted_at
        tx.updated_at = change.updated_at
        tx.revision = change.revision
        await db.flush()
        await _write_sync_audit(db, change, client_id, before=before, after=ledger_transaction_to_dict(tx))
        return _applied(change)

    if tx is None:
        tx = LedgerTransaction(id=change.entity_id, user_id=change.user_id)
        db.add(tx)

    before = ledger_transaction_to_dict(tx) if tx.created_at is not None else None
    data = change.data
    amount = data.get("amount")
    if amount is None or float(amount) <= 0:
        return _skipped(change, "invalid_amount", tx.revision if tx.created_at is not None else None)

    tx.direction = data.get("direction") or "expense"
    tx.amount = float(amount)
    tx.currency = data.get("currency") or "CNY"
    tx.account_id = data.get("account_id")
    tx.category_id = data.get("category_id")
    tx.merchant = data.get("merchant")
    tx.note = data.get("note")
    tx.occurred_at = _datetime_value(data.get("occurred_at"), fallback=change.updated_at)
    tx.source = data.get("source") or change.source
    tx.source_capture_id = data.get("source_capture_id")
    tx.import_batch_id = data.get("import_batch_id")
    tx.confidence = data.get("confidence")
    tx.status = data.get("status") or "active"
    tx.revision = change.revision
    if tx.created_at is None:
        tx.created_at = change.created_at or change.updated_at
    tx.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(db, change, client_id, before=before, after=ledger_transaction_to_dict(tx))
    return _applied(change)


async def _find_entity(db: AsyncSession, model: type[Any], change: SyncChange) -> Any | None:
    result = await db.execute(
        select(model).where(model.id == change.entity_id, model.user_id == change.user_id)
    )
    return result.scalar_one_or_none()


def _is_stale(entity: Any | None, change: SyncChange) -> bool:
    return entity is not None and entity.revision >= change.revision


def _applied(change: SyncChange) -> SyncApplyResult:
    return SyncApplyResult(
        entity_type=change.entity_type,
        entity_id=change.entity_id,
        operation=change.operation,
        status="applied",
        revision=change.revision,
    )


def _skipped(change: SyncChange, reason: str, revision: int | None) -> SyncApplyResult:
    return SyncApplyResult(
        entity_type=change.entity_type,
        entity_id=change.entity_id,
        operation=change.operation,
        status="skipped",
        revision=revision,
        reason=reason,
    )


def _memo_snapshot(memo: Memo) -> dict:
    return json_serialize(memo_to_response(memo).model_dump())


def _valid_month_period(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    parts = value.split("-")
    if len(parts) != 2 or len(parts[0]) != 4 or len(parts[1]) != 2:
        return False
    if not parts[0].isdigit() or not parts[1].isdigit():
        return False
    month = int(parts[1])
    return 1 <= month <= 12


def _datetime_value(value: Any, *, fallback: datetime | None = None) -> datetime | None:
    if value is None:
        return fallback
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        normalized = value.replace("Z", "+00:00")
        return datetime.fromisoformat(normalized)
    return fallback


async def _write_sync_audit(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
    *,
    before: dict | None,
    after: dict | None,
) -> None:
    db.add(
        AuditLog(
            user_id=change.user_id,
            actor_type="system",
            actor_id=client_id,
            action=f"sync.{change.operation}",
            entity_type=change.entity_type,
            entity_id=change.entity_id,
            before_snapshot=before,
            after_snapshot=after,
            source_channel="powersync",
            tool_name="cloud-sync",
            request_id=client_id,
        )
    )
