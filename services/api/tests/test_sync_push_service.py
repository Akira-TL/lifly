from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import pytest

from app.db.models import (
    AuditLog,
    LedgerBudget,
    LedgerCategory,
    LedgerTransaction,
    McpCaptureTurn,
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
        if isinstance(
            item,
            (Memo, Task, LedgerTransaction, LedgerBudget, Reminder, McpCaptureTurn),
        ):
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
async def test_sync_push_memo_partial_restore_preserves_unsent_fields() -> None:
    session = FakeAsyncSession()
    created_at = datetime(2026, 7, 3, 8, tzinfo=timezone.utc)
    deleted_at = datetime(2026, 7, 3, 9, tzinfo=timezone.utc)
    memo = Memo(
        id="memo-restore-sync",
        user_id="local-dev",
        type="journal",
        title="Preserve memo",
        content_markdown="keep body",
        tags=["keep"],
        mood="平静",
        source_capture_id="capture-memo",
        source="flutter",
        status="user_trashed",
        deleted_at=deleted_at,
        revision=2,
        created_at=created_at,
        updated_at=deleted_at,
    )
    session.add(memo)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "memo",
                "operation": "upsert",
                "entity_id": memo.id,
                "revision": 3,
                "updated_at": datetime(2026, 7, 3, 10, tzinfo=timezone.utc),
                "data": {"status": "active"},
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 1
    assert memo.status == "active"
    assert memo.deleted_at is None
    assert memo.type == "journal"
    assert memo.title == "Preserve memo"
    assert memo.content_markdown == "keep body"
    assert memo.tags == ["keep"]
    assert memo.mood == "平静"
    assert memo.source_capture_id == "capture-memo"
    assert memo.source == "flutter"
    assert memo.revision == 3


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
async def test_sync_push_task_partial_restore_preserves_unsent_fields() -> None:
    session = FakeAsyncSession()
    created_at = datetime(2026, 7, 3, 9, tzinfo=timezone.utc)
    deleted_at = datetime(2026, 7, 3, 10, tzinfo=timezone.utc)
    due_at = datetime(2026, 7, 4, 18, tzinfo=timezone.utc)
    remind_at = datetime(2026, 7, 4, 16, tzinfo=timezone.utc)
    completed_at = datetime(2026, 7, 3, 8, tzinfo=timezone.utc)
    existing = Task(
        id="task-restore-sync",
        user_id="local-dev",
        title="Preserve restored task",
        description="keep description",
        due_at=due_at,
        remind_at=remind_at,
        priority="high",
        task_status="done",
        completed_at=completed_at,
        source_capture_id="capture-1",
        source="flutter",
        status="user_trashed",
        deleted_at=deleted_at,
        revision=4,
        created_at=created_at,
        updated_at=deleted_at,
    )
    session.add(existing)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "task",
                "operation": "upsert",
                "entity_id": existing.id,
                "revision": 5,
                "updated_at": datetime(2026, 7, 3, 11, tzinfo=timezone.utc),
                "data": {"status": "active"},
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 1
    assert existing.status == "active"
    assert existing.deleted_at is None
    assert existing.title == "Preserve restored task"
    assert existing.description == "keep description"
    assert existing.due_at == due_at
    assert existing.remind_at == remind_at
    assert existing.priority == "high"
    assert existing.task_status == "done"
    assert existing.completed_at == completed_at
    assert existing.source_capture_id == "capture-1"
    assert existing.source == "flutter"
    assert existing.revision == 5


@pytest.mark.anyio
async def test_sync_push_expense_partial_restore_preserves_unsent_fields() -> None:
    session = FakeAsyncSession()
    created_at = datetime(2026, 7, 3, 8, tzinfo=timezone.utc)
    deleted_at = datetime(2026, 7, 3, 9, tzinfo=timezone.utc)
    occurred_at = datetime(2026, 7, 2, 18, tzinfo=timezone.utc)
    tx = LedgerTransaction(
        id="expense-restore-sync",
        user_id="local-dev",
        direction="expense",
        amount=36.5,
        currency="CNY",
        account_id="account-1",
        category_id="category-1",
        merchant="Preserve merchant",
        note="keep note",
        occurred_at=occurred_at,
        source="flutter",
        source_capture_id="capture-expense",
        import_batch_id="batch-1",
        confidence=0.9,
        status="user_trashed",
        deleted_at=deleted_at,
        revision=4,
        created_at=created_at,
        updated_at=deleted_at,
    )
    session.add(tx)
    request = SyncPushRequest(
        client_id="client-a",
        changes=[
            {
                "entity_type": "expense",
                "operation": "upsert",
                "entity_id": tx.id,
                "revision": 5,
                "updated_at": datetime(2026, 7, 3, 10, tzinfo=timezone.utc),
                "data": {"status": "active"},
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 1
    assert response.skipped == 0
    assert tx.status == "active"
    assert tx.deleted_at is None
    assert tx.direction == "expense"
    assert float(tx.amount) == 36.5
    assert tx.currency == "CNY"
    assert tx.account_id == "account-1"
    assert tx.category_id == "category-1"
    assert tx.merchant == "Preserve merchant"
    assert tx.note == "keep note"
    assert tx.occurred_at == occurred_at
    assert tx.source == "flutter"
    assert tx.source_capture_id == "capture-expense"
    assert tx.import_batch_id == "batch-1"
    assert tx.confidence == 0.9
    assert tx.revision == 5


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
async def test_sync_push_updates_capture_turn_without_clearing_history() -> None:
    session = FakeAsyncSession()
    now = datetime(2026, 7, 12, 10, tzinfo=timezone.utc)
    turn = McpCaptureTurn(
        id="turn-sync-1",
        user_id="local-dev",
        capture_id="capture-sync-1",
        turn_index=1,
        role="assistant",
        text="保留的历史文本",
        asset_ids=["asset-1"],
        asset_context=[
            {
                "asset_id": "asset-1",
                "status": "unsupported",
                "extractor": "pdf_adapter",
                "required_capability": "pdf_text_extraction",
            }
        ],
        actions=[
            {
                "type": "memo_create",
                "payload": {"title": "原候选动作"},
                "confidence": 0.8,
            }
        ],
        selected_action_indexes=[],
        result_entities=[],
        turn_status="parsed",
        source_channel="flutter",
        revision=2,
        created_at=now,
        updated_at=now,
    )
    session.add(turn)
    request = SyncPushRequest(
        client_id="client-capture",
        changes=[
            {
                "entity_type": "capture_turn",
                "operation": "upsert",
                "entity_id": "turn-sync-1",
                "revision": 3,
                "updated_at": now,
                "data": {
                    "turn_status": "committed",
                    "undo_token": "undo-sync-1",
                    "selected_action_indexes": [0],
                    "result_entities": [{"type": "memo", "id": "memo-sync-1"}],
                },
            }
        ],
    )

    response = await sync_service.apply_sync_push(session, request)  # type: ignore[arg-type]

    assert response.applied == 1
    assert turn.turn_status == "committed"
    assert turn.undo_token == "undo-sync-1"
    assert turn.text == "保留的历史文本"
    assert turn.asset_ids == ["asset-1"]
    assert turn.asset_context[0]["required_capability"] == "pdf_text_extraction"
    assert turn.actions[0]["payload"]["title"] == "原候选动作"
    assert turn.result_entities == [{"type": "memo", "id": "memo-sync-1"}]
    assert turn.revision == 3
    assert session.audit_logs[0].entity_type == "capture_turn"


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
