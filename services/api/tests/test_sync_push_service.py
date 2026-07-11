from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import pytest

from app.db.models import (
    AuditLog,
    LedgerBudget,
    LedgerCategory,
    LedgerTransaction,
    Memo,
    Reminder,
    Task,
)
from app.modules.sync import service as sync_service
from app.modules.sync.schemas import SyncChange, SyncPushRequest


class FakeAsyncSession:
    def __init__(self) -> None:
        self.entities: dict[tuple[type[Any], str, str], Any] = {}
        self.audit_logs: list[AuditLog] = []
        self.scalar_results: list[Any | None] = []
        self.flush_count = 0

    def add(self, item: Any) -> None:
        if isinstance(item, AuditLog):
            self.audit_logs.append(item)
            return
        if isinstance(item, (Memo, Task, LedgerTransaction, LedgerBudget, Reminder)):
            self.entities[(type(item), item.id, item.user_id)] = item
            return
        raise TypeError(f"Unsupported fake session item: {type(item)!r}")

    async def flush(self) -> None:
        self.flush_count += 1

    async def scalar(self, query: Any) -> Any | None:
        if self.scalar_results:
            return self.scalar_results.pop(0)
        return None


async def fake_find_entity(
    db: FakeAsyncSession,
    model: type[Any],
    change: SyncChange,
) -> Any | None:
    return db.entities.get((model, change.entity_id, change.user_id))


@pytest.fixture(autouse=True)
def patch_find_entity(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(sync_service, "_find_entity", fake_find_entity)


@pytest.mark.anyio
async def test_sync_push_applies_memo_upsert() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 3, 10, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "memo",
                "operation": "upsert",
                "entity_id": "memo-sync-1",
                "revision": 1,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "type": "memo",
                    "title": "Synced memo",
                    "content_markdown": "from powersync",
                    "tags": ["sync"],
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    memo = session.entities[(Memo, "memo-sync-1", "local-dev")]
    assert response.applied == 1
    assert response.skipped == 0
    assert memo.title == "Synced memo"
    assert memo.revision == 1
    assert len(session.audit_logs) == 1
    assert session.audit_logs[0].action == "sync.upsert"
    assert session.audit_logs[0].entity_type == "memo"


@pytest.mark.anyio
async def test_sync_push_marks_memo_removed() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 3, 10, tzinfo=timezone.utc)
    memo = Memo(
        id="memo-sync-1",
        user_id="local-dev",
        type="memo",
        title="Synced memo",
        content_markdown="from powersync",
        status="active",
        revision=1,
        created_at=now,
        updated_at=now,
    )
    session.add(memo)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "memo",
                "operation": "delete",
                "entity_id": "memo-sync-1",
                "revision": 2,
                "updated_at": now,
                "deleted_at": now,
                "data": {"status": "deleted"},
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 1
    assert memo.status == "deleted"
    assert memo.revision == 2
    assert session.audit_logs[0].action == "sync.delete"


@pytest.mark.anyio
async def test_sync_push_skips_stale_task_revision() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 3, 11, tzinfo=timezone.utc)
    existing = Task(
        id="task-sync-1",
        user_id="local-dev",
        title="Existing task",
        revision=3,
        created_at=now,
        updated_at=now,
    )
    session.add(existing)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "task",
                "operation": "upsert",
                "entity_id": "task-sync-1",
                "revision": 2,
                "updated_at": now,
                "data": {"title": "Stale title"},
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 0
    assert response.skipped == 1
    assert response.results[0].reason == "stale_revision"
    assert existing.title == "Existing task"
    assert len(session.audit_logs) == 0


@pytest.mark.anyio
async def test_sync_push_applies_expense_upsert() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 3, 12, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "expense",
                "operation": "upsert",
                "entity_id": "tx-sync-1",
                "revision": 1,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "direction": "expense",
                    "amount": 12.5,
                    "currency": "CNY",
                    "merchant": "Sync Merchant",
                    "occurred_at": now.isoformat(),
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    tx = session.entities[(LedgerTransaction, "tx-sync-1", "local-dev")]
    assert response.applied == 1
    assert float(tx.amount) == 12.5
    assert tx.merchant == "Sync Merchant"
    assert tx.revision == 1
    assert session.audit_logs[0].entity_type == "expense"
    assert session.audit_logs[0].action == "sync.upsert"


@pytest.mark.anyio
async def test_sync_push_applies_budget_upsert() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 8, 9, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-budget",
        changes=[
            {
                "entity_type": "ledger_budget",
                "operation": "upsert",
                "entity_id": "budget-sync-1",
                "revision": 1,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "period_type": "month",
                    "period_key": "2026-07",
                    "category_id": None,
                    "amount": 1200,
                    "currency": "CNY",
                    "alert_threshold": 0.8,
                    "status": "active",
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    budget = session.entities[(LedgerBudget, "budget-sync-1", "local-dev")]
    assert response.applied == 1
    assert float(budget.amount) == 1200
    assert budget.category_id is None
    assert budget.revision == 1
    assert session.audit_logs[0].entity_type == "ledger_budget"
    assert session.audit_logs[0].action == "sync.upsert"


@pytest.mark.anyio
async def test_sync_push_rejects_invalid_budget_threshold() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 8, 9, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-budget",
        changes=[
            {
                "entity_type": "ledger_budget",
                "operation": "upsert",
                "entity_id": "budget-invalid-threshold",
                "revision": 1,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "period_type": "month",
                    "period_key": "2026-07",
                    "amount": 1200,
                    "alert_threshold": 1.2,
                    "status": "active",
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 0
    assert response.results[0].reason == "invalid_alert_threshold"
    assert not session.audit_logs


@pytest.mark.anyio
async def test_sync_push_rejects_non_expense_budget_category() -> None:
    session = FakeAsyncSession()
    session.scalar_results.append(
        LedgerCategory(
            id="salary",
            user_id="local-dev",
            name="工资",
            type="income",
            status="active",
        )
    )
    now = datetime(2026, 7, 8, 9, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-budget",
        changes=[
            {
                "entity_type": "ledger_budget",
                "operation": "upsert",
                "entity_id": "budget-income-category",
                "revision": 1,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "period_type": "month",
                    "period_key": "2026-07",
                    "category_id": "salary",
                    "amount": 1200,
                    "alert_threshold": 0.8,
                    "status": "active",
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 0
    assert response.results[0].reason == "invalid_budget_category_type"
    assert not session.audit_logs


@pytest.mark.anyio
async def test_sync_push_applies_reminder_delivery_state() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    request = SyncPushRequest(
        client_id="client-reminder",
        changes=[
            {
                "entity_type": "reminder",
                "operation": "upsert",
                "entity_id": "reminder-sync-1",
                "revision": 2,
                "created_at": now,
                "updated_at": now,
                "data": {
                    "target_type": "task",
                    "target_id": "task-1",
                    "remind_at": now.isoformat(),
                    "channel": "app",
                    "reminder_status": "failed",
                    "attempt_count": 1,
                    "max_attempts": 3,
                    "next_attempt_at": (now.replace(minute=11)).isoformat(),
                    "last_attempt_at": now.isoformat(),
                    "failed_at": now.isoformat(),
                    "last_error": "permission denied",
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    reminder = session.entities[(Reminder, "reminder-sync-1", "local-dev")]
    assert response.applied == 1
    assert reminder.reminder_status == "failed"
    assert reminder.attempt_count == 1
    assert reminder.max_attempts == 3
    assert reminder.last_error == "permission denied"
    assert reminder.revision == 2
    assert session.audit_logs[0].entity_type == "reminder"
