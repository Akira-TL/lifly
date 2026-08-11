from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import pytest
from fastapi import HTTPException

from app.db.models import AuditLog, LedgerTransaction, Memo, Task
from app.modules import trash


class _ScalarResult:
    def __init__(self, item: Any | None) -> None:
        self.item = item

    def scalar_one_or_none(self) -> Any | None:
        return self.item


class _FakeSession:
    def __init__(self, item: Any | None) -> None:
        self.item = item
        self.audit_logs: list[AuditLog] = []
        self.commit_count = 0

    async def execute(self, _query: Any) -> _ScalarResult:
        return _ScalarResult(self.item)

    def add(self, item: Any) -> None:
        if isinstance(item, AuditLog):
            self.audit_logs.append(item)

    async def commit(self) -> None:
        self.commit_count += 1


def _memo() -> Memo:
    now = datetime(2026, 8, 11, 5, tzinfo=timezone.utc)
    return Memo(
        id="memo-trash-1",
        user_id="local-dev",
        type="memo",
        title="待恢复备忘",
        content_markdown="正文",
        tags=["恢复"],
        status="user_trashed",
        deleted_at=now,
        revision=3,
        created_at=now,
        updated_at=now,
    )


def _task() -> Task:
    now = datetime(2026, 8, 11, 5, tzinfo=timezone.utc)
    return Task(
        id="task-trash-1",
        user_id="local-dev",
        title="待恢复任务",
        description="保留原始任务字段",
        priority="high",
        task_status="todo",
        status="user_trashed",
        deleted_at=now,
        revision=4,
        created_at=now,
        updated_at=now,
    )


def _transaction() -> LedgerTransaction:
    now = datetime(2026, 8, 11, 5, tzinfo=timezone.utc)
    return LedgerTransaction(
        id="tx-trash-1",
        user_id="local-dev",
        direction="expense",
        amount=Decimal("28.60"),
        currency="CNY",
        merchant="咖啡店",
        occurred_at=now,
        source="manual",
        status="user_trashed",
        deleted_at=now,
        revision=2,
        created_at=now,
        updated_at=now,
    )


@pytest.mark.anyio
@pytest.mark.parametrize(
    ("entity_type", "item", "expected_entity_type"),
    [
        ("memo", _memo(), "memo"),
        ("task", _task(), "task"),
        ("ledger_transaction", _transaction(), "ledger_transaction"),
    ],
)
async def test_restore_reactivates_entity_with_revision_and_audit(
    entity_type: str,
    item: Memo | Task | LedgerTransaction,
    expected_entity_type: str,
) -> None:
    before_revision = item.revision
    session = _FakeSession(item)

    response = await trash.restore(
        entity_type,
        item.id,
        db=session,  # type: ignore[arg-type]
    )

    assert response.data["status"] == "active"
    assert response.data["revision"] == before_revision + 1
    assert item.status == "active"
    assert item.deleted_at is None
    assert item.revision == before_revision + 1
    assert session.commit_count == 1
    assert len(session.audit_logs) == 1
    audit = session.audit_logs[0]
    assert audit.action == "restore"
    assert audit.entity_type == expected_entity_type
    assert audit.entity_id == item.id
    assert audit.before_snapshot is not None
    assert audit.before_snapshot["status"] == "user_trashed"
    assert audit.after_snapshot is not None
    assert audit.after_snapshot["status"] == "active"
    assert audit.after_snapshot["revision"] == before_revision + 1


@pytest.mark.anyio
async def test_restore_rejects_non_trashed_entity() -> None:
    item = _task()
    item.status = "active"
    item.deleted_at = None
    session = _FakeSession(item)

    with pytest.raises(HTTPException) as exc_info:
        await trash.restore("task", item.id, db=session)  # type: ignore[arg-type]

    assert exc_info.value.status_code == 409
    assert session.commit_count == 0
    assert session.audit_logs == []
