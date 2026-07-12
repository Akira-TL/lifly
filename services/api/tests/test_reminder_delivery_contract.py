from __future__ import annotations

from datetime import datetime, timedelta, timezone
import inspect
from typing import Any

import pytest

from app.db.models import AuditLog, Reminder
from app.modules.tasks import reminder_delivery_service as delivery
from app.modules.tasks import router as task_router


class _ScalarResult:
    def __init__(self, items: list[Any]) -> None:
        self.items = items

    def scalars(self) -> "_ScalarResult":
        return self

    def all(self) -> list[Any]:
        return self.items

    def scalar_one_or_none(self) -> Any | None:
        return self.items[0] if self.items else None


class _FakeSession:
    def __init__(self, items: list[Any] | None = None) -> None:
        self.items = items or []
        self.audit_logs: list[AuditLog] = []
        self.flush_count = 0

    async def execute(self, _query: Any) -> _ScalarResult:
        return _ScalarResult(self.items)

    def add(self, item: Any) -> None:
        if isinstance(item, AuditLog):
            self.audit_logs.append(item)

    async def flush(self) -> None:
        self.flush_count += 1


def _reminder(
    *,
    status: str = "pending",
    attempt_count: int = 0,
    dispatch_token: str | None = None,
) -> Reminder:
    now = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    return Reminder(
        id="reminder-1",
        user_id="local-dev",
        target_type="task",
        target_id="task-1",
        remind_at=now - timedelta(minutes=1),
        channel="app",
        reminder_status=status,
        attempt_count=attempt_count,
        max_attempts=3,
        next_attempt_at=now - timedelta(minutes=1),
        dispatch_token=dispatch_token,
        revision=2,
        created_at=now - timedelta(days=1),
        updated_at=now - timedelta(minutes=2),
    )


def test_reminder_model_and_dispatch_routes_exist() -> None:
    source = inspect.getsource(task_router)
    columns = Reminder.__table__.columns

    assert Reminder.__tablename__ == "reminders"
    for name in (
        "attempt_count",
        "max_attempts",
        "next_attempt_at",
        "last_attempt_at",
        "delivered_at",
        "failed_at",
        "cancelled_at",
        "last_error",
        "external_id",
        "dispatch_token",
        "lease_until",
        "revision",
        "updated_at",
    ):
        assert name in columns
    assert '@router.post("/reminders/claim"' in source
    assert '@router.post("/reminders/{reminder_id}/delivered"' in source
    assert '@router.post("/reminders/{reminder_id}/failed"' in source
    assert '@router.post("/reminders/{reminder_id}/retry"' in source
    assert '@router.post("/reminders/{reminder_id}/cancel"' in source


@pytest.mark.anyio
async def test_claim_due_reminder_creates_lease_and_dispatch_token() -> None:
    now = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    reminder = _reminder(status="failed", attempt_count=1)
    session = _FakeSession([reminder])

    claimed = await delivery.claim_due_reminders(
        session,  # type: ignore[arg-type]
        user_id="local-dev",
        now=now,
        lease_seconds=120,
    )

    assert claimed == [reminder]
    assert reminder.reminder_status == "pending"
    assert reminder.attempt_count == 2
    assert reminder.dispatch_token
    assert reminder.lease_until == now + timedelta(seconds=120)
    assert reminder.next_attempt_at is None
    assert reminder.revision == 3
    assert session.audit_logs[0].action == "reminder.dispatch.claim"


@pytest.mark.anyio
async def test_failed_reminder_schedules_retry_and_manual_retry_resets_attempts(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    reminder = _reminder(attempt_count=2, dispatch_token="claim-token")
    session = _FakeSession()

    async def load_reminder(*_args: Any, **_kwargs: Any) -> Reminder:
        return reminder

    monkeypatch.setattr(delivery, "_load_reminder", load_reminder)

    failed = await delivery.mark_reminder_failed(
        session,  # type: ignore[arg-type]
        reminder_id=reminder.id,
        user_id=reminder.user_id,
        dispatch_token="claim-token",
        error="notification permission denied",
        retry_after_seconds=30,
        now=now,
    )

    assert failed.reminder_status == "failed"
    assert failed.next_attempt_at == now + timedelta(seconds=30)
    assert failed.last_error == "notification permission denied"
    assert failed.dispatch_token is None

    retried = await delivery.retry_reminder(
        session,  # type: ignore[arg-type]
        reminder_id=reminder.id,
        user_id=reminder.user_id,
        reset_attempts=True,
        now=now + timedelta(minutes=1),
    )

    assert retried.reminder_status == "pending"
    assert retried.attempt_count == 0
    assert retried.last_error is None
    assert retried.next_attempt_at == now + timedelta(minutes=1)


@pytest.mark.anyio
async def test_delivered_transition_is_idempotent_and_rejects_stale_claim(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    reminder = _reminder(attempt_count=1, dispatch_token="claim-token")
    session = _FakeSession()

    async def load_reminder(*_args: Any, **_kwargs: Any) -> Reminder:
        return reminder

    monkeypatch.setattr(delivery, "_load_reminder", load_reminder)

    with pytest.raises(delivery.ReminderStateError):
        await delivery.mark_reminder_delivered(
            session,  # type: ignore[arg-type]
            reminder_id=reminder.id,
            user_id=reminder.user_id,
            dispatch_token="stale-token",
            now=now,
        )

    delivered = await delivery.mark_reminder_delivered(
        session,  # type: ignore[arg-type]
        reminder_id=reminder.id,
        user_id=reminder.user_id,
        dispatch_token="claim-token",
        external_id="android-notification-1",
        now=now,
    )
    repeated = await delivery.mark_reminder_delivered(
        session,  # type: ignore[arg-type]
        reminder_id=reminder.id,
        user_id=reminder.user_id,
        dispatch_token="other-token",
        now=now,
    )

    assert delivered.reminder_status == "delivered"
    assert delivered.external_id == "android-notification-1"
    assert repeated is delivered
    assert len(session.audit_logs) == 1
