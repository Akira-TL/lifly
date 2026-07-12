from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditLog, Reminder
from app.schemas.common import json_serialize

REMINDER_STATUSES = {"pending", "delivered", "failed", "cancelled"}
DISPATCHABLE_STATUSES = {"pending", "failed"}


class ReminderNotFoundError(LookupError):
    pass


class ReminderStateError(RuntimeError):
    pass


def reminder_to_dict(reminder: Reminder) -> dict[str, object]:
    return json_serialize(
        {
            "id": reminder.id,
            "user_id": reminder.user_id,
            "target_type": reminder.target_type,
            "target_id": reminder.target_id,
            "remind_at": reminder.remind_at,
            "channel": reminder.channel,
            "reminder_status": reminder.reminder_status,
            "attempt_count": reminder.attempt_count,
            "max_attempts": reminder.max_attempts,
            "next_attempt_at": reminder.next_attempt_at,
            "last_attempt_at": reminder.last_attempt_at,
            "delivered_at": reminder.delivered_at,
            "failed_at": reminder.failed_at,
            "cancelled_at": reminder.cancelled_at,
            "last_error": reminder.last_error,
            "external_id": reminder.external_id,
            "dispatch_token": reminder.dispatch_token,
            "lease_until": reminder.lease_until,
            "revision": reminder.revision,
            "created_at": reminder.created_at,
            "updated_at": reminder.updated_at,
        }
    )


async def claim_due_reminders(
    db: AsyncSession,
    *,
    user_id: str,
    limit: int = 20,
    now: datetime | None = None,
    lease_seconds: int = 120,
) -> list[Reminder]:
    claimed_at = _utc(now or datetime.now(timezone.utc))
    query = (
        select(Reminder)
        .where(
            Reminder.user_id == user_id,
            Reminder.target_type == "task",
            Reminder.reminder_status.in_(DISPATCHABLE_STATUSES),
            Reminder.remind_at <= claimed_at,
            Reminder.attempt_count < Reminder.max_attempts,
            or_(Reminder.next_attempt_at.is_(None), Reminder.next_attempt_at <= claimed_at),
            or_(Reminder.lease_until.is_(None), Reminder.lease_until <= claimed_at),
        )
        .order_by(Reminder.remind_at.asc(), Reminder.created_at.asc())
        .limit(limit)
        .with_for_update(skip_locked=True)
    )
    result = await db.execute(query)
    reminders = list(result.scalars().all())
    lease_until = claimed_at + timedelta(seconds=lease_seconds)
    for reminder in reminders:
        before = reminder_to_dict(reminder)
        reminder.reminder_status = "pending"
        reminder.attempt_count += 1
        reminder.last_attempt_at = claimed_at
        reminder.next_attempt_at = None
        reminder.dispatch_token = uuid4().hex
        reminder.lease_until = lease_until
        reminder.updated_at = claimed_at
        reminder.revision += 1
        await _write_reminder_audit(
            db,
            reminder=reminder,
            action="reminder.dispatch.claim",
            before=before,
            after=reminder_to_dict(reminder),
        )
    await db.flush()
    return reminders


async def mark_reminder_delivered(
    db: AsyncSession,
    *,
    reminder_id: str,
    user_id: str,
    dispatch_token: str,
    external_id: str | None = None,
    now: datetime | None = None,
) -> Reminder:
    reminder = await _load_reminder(db, reminder_id, user_id)
    if reminder.reminder_status == "delivered":
        return reminder
    _require_active_claim(reminder, dispatch_token)
    delivered_at = _utc(now or datetime.now(timezone.utc))
    before = reminder_to_dict(reminder)
    reminder.reminder_status = "delivered"
    reminder.delivered_at = delivered_at
    reminder.failed_at = None
    reminder.cancelled_at = None
    reminder.last_error = None
    reminder.external_id = external_id or reminder.external_id
    reminder.dispatch_token = None
    reminder.lease_until = None
    reminder.next_attempt_at = None
    reminder.updated_at = delivered_at
    reminder.revision += 1
    await _write_reminder_audit(
        db,
        reminder=reminder,
        action="reminder.delivered",
        before=before,
        after=reminder_to_dict(reminder),
    )
    await db.flush()
    return reminder


async def mark_reminder_failed(
    db: AsyncSession,
    *,
    reminder_id: str,
    user_id: str,
    dispatch_token: str,
    error: str,
    retry_after_seconds: int | None = None,
    now: datetime | None = None,
) -> Reminder:
    reminder = await _load_reminder(db, reminder_id, user_id)
    _require_active_claim(reminder, dispatch_token)
    failed_at = _utc(now or datetime.now(timezone.utc))
    before = reminder_to_dict(reminder)
    reminder.reminder_status = "failed"
    reminder.failed_at = failed_at
    reminder.last_error = error[:4096]
    reminder.dispatch_token = None
    reminder.lease_until = None
    reminder.next_attempt_at = _next_retry_at(
        reminder,
        failed_at,
        retry_after_seconds=retry_after_seconds,
    )
    reminder.updated_at = failed_at
    reminder.revision += 1
    await _write_reminder_audit(
        db,
        reminder=reminder,
        action="reminder.failed",
        before=before,
        after=reminder_to_dict(reminder),
    )
    await db.flush()
    return reminder


async def retry_reminder(
    db: AsyncSession,
    *,
    reminder_id: str,
    user_id: str,
    reset_attempts: bool = True,
    now: datetime | None = None,
) -> Reminder:
    reminder = await _load_reminder(db, reminder_id, user_id)
    if reminder.reminder_status == "pending":
        return reminder
    if reminder.reminder_status != "failed":
        raise ReminderStateError(
            f"Reminder {reminder.id} cannot retry from {reminder.reminder_status}"
        )
    retry_at = _utc(now or datetime.now(timezone.utc))
    before = reminder_to_dict(reminder)
    reminder.reminder_status = "pending"
    if reset_attempts:
        reminder.attempt_count = 0
    reminder.next_attempt_at = retry_at
    reminder.failed_at = None
    reminder.last_error = None
    reminder.dispatch_token = None
    reminder.lease_until = None
    reminder.updated_at = retry_at
    reminder.revision += 1
    await _write_reminder_audit(
        db,
        reminder=reminder,
        action="reminder.retry",
        before=before,
        after=reminder_to_dict(reminder),
    )
    await db.flush()
    return reminder


async def cancel_reminder(
    db: AsyncSession,
    *,
    reminder_id: str,
    user_id: str,
    now: datetime | None = None,
    source_channel: str = "api",
) -> Reminder:
    reminder = await _load_reminder(db, reminder_id, user_id)
    return await _cancel_reminder_record(
        db,
        reminder,
        now=_utc(now or datetime.now(timezone.utc)),
        source_channel=source_channel,
    )


async def cancel_active_reminders_for_task(
    db: AsyncSession,
    *,
    task_id: str,
    user_id: str,
    now: datetime | None = None,
    source_channel: str = "system",
) -> list[Reminder]:
    cancelled_at = _utc(now or datetime.now(timezone.utc))
    result = await db.execute(
        select(Reminder).where(
            Reminder.user_id == user_id,
            Reminder.target_type == "task",
            Reminder.target_id == task_id,
            Reminder.reminder_status.in_(DISPATCHABLE_STATUSES),
        )
    )
    reminders = list(result.scalars().all())
    for reminder in reminders:
        await _cancel_reminder_record(
            db,
            reminder,
            now=cancelled_at,
            source_channel=source_channel,
        )
    await db.flush()
    return reminders


async def _cancel_reminder_record(
    db: AsyncSession,
    reminder: Reminder,
    *,
    now: datetime,
    source_channel: str,
) -> Reminder:
    if reminder.reminder_status == "cancelled":
        return reminder
    if reminder.reminder_status == "delivered":
        raise ReminderStateError(f"Delivered reminder {reminder.id} cannot be cancelled")
    before = reminder_to_dict(reminder)
    reminder.reminder_status = "cancelled"
    reminder.cancelled_at = now
    reminder.next_attempt_at = None
    reminder.dispatch_token = None
    reminder.lease_until = None
    reminder.updated_at = now
    reminder.revision += 1
    await _write_reminder_audit(
        db,
        reminder=reminder,
        action="reminder.cancelled",
        before=before,
        after=reminder_to_dict(reminder),
        source_channel=source_channel,
    )
    return reminder


async def _load_reminder(
    db: AsyncSession,
    reminder_id: str,
    user_id: str,
) -> Reminder:
    result = await db.execute(
        select(Reminder).where(Reminder.id == reminder_id, Reminder.user_id == user_id)
    )
    reminder = result.scalar_one_or_none()
    if reminder is None:
        raise ReminderNotFoundError(f"Reminder not found: {reminder_id}")
    return reminder


def _require_active_claim(reminder: Reminder, dispatch_token: str) -> None:
    if reminder.reminder_status in {"delivered", "cancelled"}:
        raise ReminderStateError(
            f"Reminder {reminder.id} cannot transition from {reminder.reminder_status}"
        )
    if not reminder.dispatch_token or reminder.dispatch_token != dispatch_token:
        raise ReminderStateError(f"Reminder {reminder.id} dispatch token is stale")


def _next_retry_at(
    reminder: Reminder,
    failed_at: datetime,
    *,
    retry_after_seconds: int | None,
) -> datetime | None:
    if reminder.attempt_count >= reminder.max_attempts:
        return None
    if retry_after_seconds is None:
        retry_after_seconds = min(3600, 60 * (2 ** max(0, reminder.attempt_count - 1)))
    return failed_at + timedelta(seconds=retry_after_seconds)


async def _write_reminder_audit(
    db: AsyncSession,
    *,
    reminder: Reminder,
    action: str,
    before: dict[str, object] | None,
    after: dict[str, object] | None,
    source_channel: str = "api",
) -> None:
    db.add(
        AuditLog(
            user_id=reminder.user_id,
            actor_type="system",
            action=action,
            entity_type="reminder",
            entity_id=reminder.id,
            before_snapshot=before,
            after_snapshot=after,
            source_channel=source_channel,
            tool_name="reminder-dispatch",
        )
    )


def _utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)
