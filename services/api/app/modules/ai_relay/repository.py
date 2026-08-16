from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Protocol

from fastapi import Depends
from sqlalchemy import and_, or_, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import AiJob
from app.modules.ai_relay.contracts import AiJobEnvelope, AiJobMessageType


class AiRelayConflict(RuntimeError):
    pass


class AiRelayStore(Protocol):
    async def submit_request(self, envelope: AiJobEnvelope) -> AiJobEnvelope: ...

    async def next_for_target(
        self, *, account_id: str, target_device_id: str, now: datetime
    ) -> AiJobEnvelope | None: ...

    async def get_request(
        self, *, account_id: str, job_id: str
    ) -> AiJobEnvelope | None: ...

    async def delivery_status(self, *, account_id: str, job_id: str) -> str | None: ...

    async def mark_failed(self, *, account_id: str, job_id: str) -> None: ...

    async def submit_result(
        self, *, request: AiJobEnvelope, result: AiJobEnvelope
    ) -> AiJobEnvelope: ...

    async def result_for_request(
        self,
        *,
        account_id: str,
        request_job_id: str,
        requester_device_id: str,
        now: datetime,
    ) -> AiJobEnvelope | None: ...


class SqlAlchemyAiRelayStore:
    _delivery_lease = timedelta(seconds=15)

    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def submit_request(self, envelope: AiJobEnvelope) -> AiJobEnvelope:
        existing = await self._load_by_id(envelope.job_id)
        if existing is not None:
            current = _to_envelope(existing)
            if current != envelope:
                raise AiRelayConflict("AI relay job id conflict")
            return current

        idempotent = await self._db.execute(
            select(AiJob).where(
                AiJob.account_id == envelope.account_id,
                AiJob.source_device_id == envelope.source_device_id,
                AiJob.idempotency_key == envelope.idempotency_key,
                AiJob.message_type == AiJobMessageType.REQUEST.value,
            )
        )
        existing = idempotent.scalar_one_or_none()
        if existing is not None:
            current = _to_envelope(existing)
            if current != envelope:
                raise AiRelayConflict("AI relay idempotency conflict")
            return current

        model = _from_envelope(envelope, delivery_status="queued")
        self._db.add(model)
        try:
            await self._db.commit()
        except IntegrityError as exc:
            await self._db.rollback()
            raise AiRelayConflict("AI relay job conflicts with an existing request") from exc
        return envelope

    async def next_for_target(
        self, *, account_id: str, target_device_id: str, now: datetime
    ) -> AiJobEnvelope | None:
        base_scope = (
            AiJob.account_id == account_id,
            AiJob.target_device_id == target_device_id,
            AiJob.message_type == AiJobMessageType.REQUEST.value,
        )
        await self._db.execute(
            update(AiJob)
            .where(
                *base_scope,
                AiJob.delivery_status.in_(("queued", "delivered")),
                AiJob.expires_at <= now,
            )
            .values(delivery_status="expired")
        )
        result = await self._db.execute(
            select(AiJob)
            .where(
                *base_scope,
                AiJob.expires_at > now,
                or_(
                    AiJob.delivery_status == "queued",
                    and_(
                        AiJob.delivery_status == "delivered",
                        or_(
                            AiJob.next_attempt_at.is_(None),
                            AiJob.next_attempt_at <= now,
                        ),
                    ),
                ),
            )
            .order_by(AiJob.created_at, AiJob.id)
            .limit(1)
            .with_for_update(skip_locked=True)
        )
        model = result.scalar_one_or_none()
        if model is None:
            await self._db.commit()
            return None
        model.delivery_status = "delivered"
        model.delivered_at = now
        model.next_attempt_at = now + self._delivery_lease
        model.attempt_count += 1
        await self._db.commit()
        return _to_envelope(model)

    async def get_request(
        self, *, account_id: str, job_id: str
    ) -> AiJobEnvelope | None:
        result = await self._db.execute(
            select(AiJob).where(
                AiJob.id == job_id,
                AiJob.account_id == account_id,
                AiJob.message_type == AiJobMessageType.REQUEST.value,
            )
        )
        model = result.scalar_one_or_none()
        return None if model is None else _to_envelope(model)

    async def delivery_status(self, *, account_id: str, job_id: str) -> str | None:
        result = await self._db.execute(
            select(AiJob.delivery_status).where(
                AiJob.id == job_id,
                AiJob.account_id == account_id,
                AiJob.message_type == AiJobMessageType.REQUEST.value,
            )
        )
        return result.scalar_one_or_none()

    async def mark_failed(self, *, account_id: str, job_id: str) -> None:
        result = await self._db.execute(
            select(AiJob).where(
                AiJob.id == job_id,
                AiJob.account_id == account_id,
                AiJob.message_type == AiJobMessageType.REQUEST.value,
            )
        )
        model = result.scalar_one_or_none()
        if model is None:
            raise AiRelayConflict("AI relay request not found")
        if model.delivery_status == "completed":
            raise AiRelayConflict("AI relay request is already completed")
        if model.delivery_status == "expired":
            return
        model.delivery_status = "failed"
        await self._db.commit()

    async def submit_result(
        self, *, request: AiJobEnvelope, result: AiJobEnvelope
    ) -> AiJobEnvelope:
        existing = await self._load_by_id(result.job_id)
        if existing is not None:
            current = _to_envelope(existing)
            if current != result:
                raise AiRelayConflict("AI relay result job id conflict")
            return current

        request_model = await self._load_by_id(request.job_id)
        if request_model is None:
            raise AiRelayConflict("AI relay request disappeared before result submission")
        result_model = _from_envelope(result, delivery_status="queued")
        self._db.add(result_model)
        request_model.delivery_status = "completed"
        try:
            await self._db.commit()
        except IntegrityError as exc:
            await self._db.rollback()
            raise AiRelayConflict("AI relay result conflicts with an existing message") from exc
        return result

    async def result_for_request(
        self,
        *,
        account_id: str,
        request_job_id: str,
        requester_device_id: str,
        now: datetime,
    ) -> AiJobEnvelope | None:
        result = await self._db.execute(
            select(AiJob)
            .where(
                AiJob.account_id == account_id,
                AiJob.message_type == AiJobMessageType.RESULT.value,
                AiJob.correlation_id == request_job_id,
                AiJob.target_device_id == requester_device_id,
            )
            .order_by(AiJob.created_at, AiJob.id)
        )
        model = result.scalars().first()
        if model is None:
            return None
        if _as_utc(model.expires_at) <= now:
            model.delivery_status = "expired"
            await self._db.commit()
            return None
        if model.delivery_status != "delivered":
            model.delivery_status = "delivered"
            model.delivered_at = now
            model.attempt_count += 1
            await self._db.commit()
        return _to_envelope(model)

    async def _load_by_id(self, job_id: str) -> AiJob | None:
        result = await self._db.execute(select(AiJob).where(AiJob.id == job_id))
        return result.scalar_one_or_none()


def _from_envelope(envelope: AiJobEnvelope, *, delivery_status: str) -> AiJob:
    return AiJob(
        id=envelope.job_id,
        account_id=envelope.account_id,
        source_device_id=envelope.source_device_id,
        target_device_id=envelope.target_device_id,
        message_type=envelope.message_type.value,
        correlation_id=envelope.correlation_id,
        idempotency_key=envelope.idempotency_key,
        delivery_status=delivery_status,
        expires_at=envelope.expires_at,
        protocol_version=envelope.protocol_version,
        encryption_version=envelope.encryption_version,
        nonce=envelope.nonce,
        ciphertext=envelope.ciphertext,
    )


def _to_envelope(model: AiJob) -> AiJobEnvelope:
    return AiJobEnvelope(
        protocol_version=model.protocol_version,
        job_id=model.id,
        account_id=model.account_id,
        source_device_id=model.source_device_id,
        target_device_id=model.target_device_id,
        message_type=AiJobMessageType(model.message_type),
        correlation_id=model.correlation_id,
        idempotency_key=model.idempotency_key,
        expires_at=_as_utc(model.expires_at),
        encryption_version=model.encryption_version,
        nonce=model.nonce,
        ciphertext=model.ciphertext,
    )


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


async def get_ai_relay_store(
    db: AsyncSession = Depends(get_db),
) -> AiRelayStore:
    return SqlAlchemyAiRelayStore(db)
