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
    McpCaptureSession,
    McpCaptureTurn,
    Memo,
    Reminder,
    Task,
)
from app.modules.ledger.service import ledger_budget_to_dict, ledger_transaction_to_dict
from app.modules.sync.schemas import (
    PowerSyncCredentialsResponse,
    SyncApplyResult,
    SyncChange,
    SyncPushRequest,
    SyncPushResponse,
)
from app.modules.sync.snapshots import (
    capture_session_snapshot,
    capture_turn_snapshot,
    memo_snapshot,
)
from app.modules.tasks.reminder_delivery_service import reminder_to_dict
from app.modules.tasks.service import task_to_dict


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
        elif change.entity_type == "reminder":
            result = await _apply_reminder_change(db, change, request.client_id)
        elif change.entity_type == "capture_session":
            result = await _apply_capture_session_change(db, change, request.client_id)
        elif change.entity_type == "capture_turn":
            result = await _apply_capture_turn_change(db, change, request.client_id)
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
        before = memo_snapshot(memo)
        memo.status = change.data.get("status") or "deleted"
        memo.deleted_at = change.deleted_at
        memo.updated_at = change.updated_at
        memo.revision = change.revision
        await db.flush()
        await _write_sync_audit(db, change, client_id, before=before, after=memo_snapshot(memo))
        return _applied(change)

    is_new = memo is None
    if memo is None:
        memo = Memo(id=change.entity_id, user_id=change.user_id)
        db.add(memo)

    before = None if is_new else memo_snapshot(memo)
    data = change.data
    if is_new or "type" in data:
        memo.type = data.get("type") or memo.type or "memo"
    if is_new or "title" in data:
        memo.title = data.get("title")
    if is_new or "content_markdown" in data:
        memo.content_markdown = data.get("content_markdown") or ""
    if is_new or "tags" in data:
        memo.tags = data.get("tags")
    if is_new or "mood" in data:
        memo.mood = data.get("mood")
    if is_new or "source_capture_id" in data:
        memo.source_capture_id = data.get("source_capture_id")
    if is_new or "status" in data:
        memo.status = data.get("status") or "active"
        if memo.status == "active":
            memo.deleted_at = None
    if is_new or "source" in data:
        memo.source = data.get("source") or change.source
    memo.revision = change.revision
    if is_new:
        memo.created_at = change.created_at or change.updated_at
    memo.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(db, change, client_id, before=before, after=memo_snapshot(memo))
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

    is_new = task is None
    if task is None:
        task = Task(id=change.entity_id, user_id=change.user_id, title="")
        db.add(task)

    before = None if is_new else task_to_dict(task)
    data = change.data
    if is_new or "title" in data:
        task.title = data.get("title") or task.title
    if is_new or "description" in data:
        task.description = data.get("description")
    if is_new or "due_at" in data:
        task.due_at = _datetime_value(data.get("due_at"))
    if is_new or "remind_at" in data:
        task.remind_at = _datetime_value(data.get("remind_at"))
    if is_new or "priority" in data:
        task.priority = data.get("priority") or "normal"
    if is_new or "task_status" in data:
        task.task_status = data.get("task_status") or "todo"
    if is_new or "completed_at" in data:
        task.completed_at = _datetime_value(data.get("completed_at"))
    if is_new or "source_capture_id" in data:
        task.source_capture_id = data.get("source_capture_id")
    if is_new or "status" in data:
        task.status = data.get("status") or "active"
        if task.status == "active":
            task.deleted_at = None
    if is_new or "source" in data:
        task.source = data.get("source") or change.source
    task.revision = change.revision
    if is_new:
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


async def _apply_reminder_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    reminder = await _find_entity(db, Reminder, change)
    if _is_stale(reminder, change):
        return _skipped(change, "stale_revision", reminder.revision)

    data = change.data
    if change.operation == "delete":
        if reminder is None:
            return _skipped(change, "missing_entity", None)
        before = reminder_to_dict(reminder)
        reminder.reminder_status = "cancelled"
        reminder.cancelled_at = change.deleted_at or change.updated_at
        reminder.next_attempt_at = None
        reminder.dispatch_token = None
        reminder.lease_until = None
        reminder.updated_at = change.updated_at
        reminder.revision = change.revision
        await db.flush()
        await _write_sync_audit(
            db,
            change,
            client_id,
            before=before,
            after=reminder_to_dict(reminder),
        )
        return _applied(change)

    target_type = data.get("target_type") or "task"
    target_id = data.get("target_id")
    remind_at = _datetime_value(data.get("remind_at"))
    status = data.get("reminder_status") or "pending"
    attempt_count = int(data.get("attempt_count") or 0)
    max_attempts = int(data.get("max_attempts") or 3)
    if target_type != "task" or not target_id:
        return _skipped(
            change,
            "invalid_target",
            reminder.revision if reminder is not None else None,
        )
    if remind_at is None:
        return _skipped(
            change,
            "invalid_remind_at",
            reminder.revision if reminder is not None else None,
        )
    if status not in {"pending", "delivered", "failed", "cancelled"}:
        return _skipped(
            change,
            "invalid_status",
            reminder.revision if reminder is not None else None,
        )
    if attempt_count < 0 or max_attempts < 1 or attempt_count > max_attempts:
        return _skipped(
            change,
            "invalid_attempts",
            reminder.revision if reminder is not None else None,
        )

    if reminder is None:
        reminder = Reminder(id=change.entity_id, user_id=change.user_id)
        db.add(reminder)
    before = reminder_to_dict(reminder) if reminder.created_at is not None else None
    reminder.target_type = target_type
    reminder.target_id = str(target_id)
    reminder.remind_at = remind_at
    reminder.channel = data.get("channel") or "app"
    reminder.reminder_status = status
    reminder.attempt_count = attempt_count
    reminder.max_attempts = max_attempts
    reminder.next_attempt_at = _datetime_value(data.get("next_attempt_at"))
    reminder.last_attempt_at = _datetime_value(data.get("last_attempt_at"))
    reminder.delivered_at = _datetime_value(data.get("delivered_at"))
    reminder.failed_at = _datetime_value(data.get("failed_at"))
    reminder.cancelled_at = _datetime_value(data.get("cancelled_at"))
    reminder.last_error = data.get("last_error")
    reminder.external_id = data.get("external_id")
    reminder.dispatch_token = data.get("dispatch_token")
    reminder.lease_until = _datetime_value(data.get("lease_until"))
    reminder.revision = change.revision
    if reminder.created_at is None:
        reminder.created_at = change.created_at or change.updated_at
    reminder.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(
        db,
        change,
        client_id,
        before=before,
        after=reminder_to_dict(reminder),
    )
    return _applied(change)


async def _apply_capture_session_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    result = await db.execute(
        select(McpCaptureSession).where(
            McpCaptureSession.capture_id == change.entity_id,
            McpCaptureSession.user_id == change.user_id,
        )
    )
    session = result.scalar_one_or_none()
    if _is_stale(session, change):
        return _skipped(change, "stale_revision", session.revision)

    if change.operation == "delete":
        if session is None:
            return _skipped(change, "missing_entity", None)
        before = capture_session_snapshot(session)
        session.session_status = "dismissed"
        session.dismissed_at = change.deleted_at or change.updated_at
        session.updated_at = change.updated_at
        session.revision = change.revision
        await db.flush()
        await _write_sync_audit(
            db,
            change,
            client_id,
            before=before,
            after=capture_session_snapshot(session),
        )
        return _applied(change)

    data = change.data
    if session is None:
        session = McpCaptureSession(
            capture_id=change.entity_id,
            user_id=change.user_id,
            original_text=str(data.get("original_text") or ""),
            actions=list(data.get("actions") or []),
            expires_at=_datetime_value(
                data.get("expires_at"),
                fallback=change.updated_at + timedelta(days=30),
            ),
        )
        db.add(session)
        before = None
    else:
        before = capture_session_snapshot(session)

    if "original_text" in data:
        session.original_text = str(data.get("original_text") or "")
    if "timezone" in data:
        session.timezone = str(data.get("timezone") or "Asia/Shanghai")
    if "locale" in data:
        session.locale = str(data.get("locale") or "zh-CN")
    if "actions" in data:
        session.actions = list(data.get("actions") or [])
    if "requires_confirmation" in data:
        session.requires_confirmation = _bool_value(
            data.get("requires_confirmation"),
            fallback=bool(session.requires_confirmation),
        )
    if "committed" in data:
        session.committed = _bool_value(
            data.get("committed"),
            fallback=bool(session.committed),
        )
    if "session_status" in data:
        session.session_status = str(data.get("session_status") or "active")
    if "source_channel" in data:
        session.source_channel = str(data.get("source_channel") or change.source)
    if "expires_at" in data:
        session.expires_at = _datetime_value(
            data.get("expires_at"),
            fallback=session.expires_at or change.updated_at + timedelta(days=30),
        )
    if "committed_at" in data:
        session.committed_at = _datetime_value(data.get("committed_at"))
    if "dismissed_at" in data:
        session.dismissed_at = _datetime_value(data.get("dismissed_at"))
    session.revision = change.revision
    if session.created_at is None:
        session.created_at = change.created_at or change.updated_at
    session.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(
        db,
        change,
        client_id,
        before=before,
        after=capture_session_snapshot(session),
    )
    return _applied(change)


async def _apply_capture_turn_change(
    db: AsyncSession,
    change: SyncChange,
    client_id: str,
) -> SyncApplyResult:
    turn = await _find_entity(db, McpCaptureTurn, change)
    if _is_stale(turn, change):
        return _skipped(change, "stale_revision", turn.revision)

    if change.operation == "delete":
        if turn is None:
            return _skipped(change, "missing_entity", None)
        before = capture_turn_snapshot(turn)
        turn.turn_status = "deleted"
        turn.updated_at = change.updated_at
        turn.revision = change.revision
        await db.flush()
        await _write_sync_audit(
            db,
            change,
            client_id,
            before=before,
            after=capture_turn_snapshot(turn),
        )
        return _applied(change)

    data = change.data
    capture_id = str(data.get("capture_id") or (turn.capture_id if turn is not None else ""))
    if not capture_id:
        return _skipped(
            change,
            "missing_capture_id",
            turn.revision if turn is not None else None,
        )
    if turn is None:
        turn = McpCaptureTurn(
            id=change.entity_id,
            user_id=change.user_id,
            capture_id=capture_id,
            turn_index=int(data.get("turn_index") or 0),
        )
        db.add(turn)
        before = None
    else:
        before = capture_turn_snapshot(turn)

    turn.capture_id = capture_id
    if "turn_index" in data:
        turn.turn_index = int(data.get("turn_index") or 0)
    if "role" in data:
        turn.role = str(data.get("role") or "assistant")
    if "text" in data:
        turn.text = data.get("text")
    if "asset_ids" in data:
        turn.asset_ids = list(data.get("asset_ids") or [])
    if "asset_context" in data:
        turn.asset_context = list(data.get("asset_context") or [])
    if "actions" in data:
        turn.actions = list(data.get("actions") or [])
    if "selected_action_indexes" in data:
        turn.selected_action_indexes = list(data.get("selected_action_indexes") or [])
    if "result_entities" in data:
        turn.result_entities = list(data.get("result_entities") or [])
    if "undo_token" in data:
        turn.undo_token = data.get("undo_token")
    if "supersedes_turn_id" in data:
        turn.supersedes_turn_id = data.get("supersedes_turn_id")
    if "turn_status" in data:
        turn.turn_status = str(data.get("turn_status") or "parsed")
    if "source_channel" in data:
        turn.source_channel = str(data.get("source_channel") or change.source)
    turn.revision = change.revision
    if turn.created_at is None:
        turn.created_at = change.created_at or change.updated_at
    turn.updated_at = change.updated_at
    await db.flush()
    await _write_sync_audit(
        db,
        change,
        client_id,
        before=before,
        after=capture_turn_snapshot(turn),
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

    is_new = tx is None
    if tx is None:
        tx = LedgerTransaction(id=change.entity_id, user_id=change.user_id)
        db.add(tx)

    before = None if is_new else ledger_transaction_to_dict(tx)
    data = change.data
    if is_new or "amount" in data:
        amount = data.get("amount")
        if amount is None or float(amount) <= 0:
            return _skipped(
                change,
                "invalid_amount",
                None if is_new else tx.revision,
            )
        tx.amount = float(amount)
    if is_new or "direction" in data:
        tx.direction = data.get("direction") or "expense"
    if is_new or "currency" in data:
        tx.currency = data.get("currency") or "CNY"
    if is_new or "account_id" in data:
        tx.account_id = data.get("account_id")
    if is_new or "category_id" in data:
        tx.category_id = data.get("category_id")
    if is_new or "merchant" in data:
        tx.merchant = data.get("merchant")
    if is_new or "note" in data:
        tx.note = data.get("note")
    if is_new or "occurred_at" in data:
        tx.occurred_at = _datetime_value(
            data.get("occurred_at"),
            fallback=change.updated_at,
        )
    if is_new or "source" in data:
        tx.source = data.get("source") or change.source
    if is_new or "source_capture_id" in data:
        tx.source_capture_id = data.get("source_capture_id")
    if is_new or "import_batch_id" in data:
        tx.import_batch_id = data.get("import_batch_id")
    if is_new or "confidence" in data:
        tx.confidence = data.get("confidence")
    if is_new or "status" in data:
        tx.status = data.get("status") or "active"
        if tx.status == "active":
            tx.deleted_at = None
    tx.revision = change.revision
    if is_new:
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



def _bool_value(value: Any, *, fallback: bool = False) -> bool:
    if value is None:
        return fallback
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "on"}:
            return True
        if normalized in {"false", "0", "no", "off", ""}:
            return False
    return fallback


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
