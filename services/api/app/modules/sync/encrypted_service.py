from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import AuthenticatedSubject
from app.db.models import EncryptedEntity
from app.modules.crypto.contracts import EncryptedEntityEnvelope
from app.modules.sync.schemas import (
    EncryptedSyncPushRequest,
    SyncApplyResult,
    SyncPushResponse,
)


async def apply_encrypted_sync_push(
    db: AsyncSession,
    subject: AuthenticatedSubject,
    request: EncryptedSyncPushRequest,
) -> SyncPushResponse:
    """Apply opaque encrypted envelopes without interpreting business payloads.

    Tenant and device identity come from the authenticated subject. Ciphertext,
    nonce and version fields are treated as opaque values; the cloud only
    resolves envelope revision conflicts and persists tombstones.
    """

    if subject.device_id is None:
        raise ValueError("encrypted sync requires authenticated device identity")
    if request.client_id != subject.device_id:
        raise PermissionError("sync client_id does not match authenticated device")

    results: list[SyncApplyResult] = []
    for envelope in request.changes:
        results.append(await _apply_envelope(db, subject, envelope))

    applied = sum(1 for item in results if item.status == "applied")
    return SyncPushResponse(
        applied=applied,
        skipped=len(results) - applied,
        results=results,
    )


async def _apply_envelope(
    db: AsyncSession,
    subject: AuthenticatedSubject,
    envelope: EncryptedEntityEnvelope,
) -> SyncApplyResult:
    operation = (
        "delete" if envelope.lifecycle_status.value == "tombstone" else "upsert"
    )
    if envelope.user_id != subject.user_id:
        return _skipped(envelope, operation, "tenant_mismatch", None)

    existing = await _find_encrypted_entity(
        db,
        entity_id=envelope.id,
        user_id=subject.user_id,
    )
    if existing is not None and existing.revision >= envelope.revision:
        return _skipped(
            envelope,
            operation,
            "stale_revision",
            existing.revision,
        )

    if existing is None:
        existing = EncryptedEntity(
            id=envelope.id,
            user_id=subject.user_id,
            entity_type=envelope.entity_type,
            revision=envelope.revision,
            lifecycle_status=envelope.lifecycle_status.value,
            key_version=envelope.key_version,
            encryption_version=envelope.encryption_version,
            schema_version=envelope.schema_version,
            nonce=envelope.nonce,
            ciphertext=envelope.ciphertext,
            created_at=envelope.updated_at,
            updated_at=envelope.updated_at,
        )
        db.add(existing)
    else:
        existing.entity_type = envelope.entity_type
        existing.revision = envelope.revision
        existing.lifecycle_status = envelope.lifecycle_status.value
        existing.key_version = envelope.key_version
        existing.encryption_version = envelope.encryption_version
        existing.schema_version = envelope.schema_version
        existing.nonce = envelope.nonce
        existing.ciphertext = envelope.ciphertext
        existing.updated_at = envelope.updated_at

    await db.flush()
    return SyncApplyResult(
        entity_type=envelope.entity_type,
        entity_id=envelope.id,
        operation=operation,
        status="applied",
        revision=envelope.revision,
    )


async def _find_encrypted_entity(
    db: AsyncSession,
    *,
    entity_id: str,
    user_id: str,
) -> EncryptedEntity | None:
    result = await db.execute(
        select(EncryptedEntity).where(
            EncryptedEntity.id == entity_id,
            EncryptedEntity.user_id == user_id,
        )
    )
    return result.scalar_one_or_none()


def _skipped(
    envelope: EncryptedEntityEnvelope,
    operation: str,
    reason: str,
    revision: int | None,
) -> SyncApplyResult:
    return SyncApplyResult(
        entity_type=envelope.entity_type,
        entity_id=envelope.id,
        operation=operation,
        status="skipped",
        revision=revision,
        reason=reason,
    )
