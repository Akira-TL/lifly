from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import AuthenticatedSubject
from app.modules.ai_relay.contracts import AiJobEnvelope, AiJobMessageType
from app.modules.ai_relay.repository import (
    AiRelayConflict,
    AiRelayStore,
    get_ai_relay_store,
)
from app.modules.auth.sessions import get_active_subject
from app.modules.devices.contracts import DeviceCapability, DeviceTrustState
from app.modules.devices.repository import (
    DeviceNotFound,
    DeviceRecord,
    DeviceRepository,
    get_device_repository,
)

router = APIRouter()


def _require_bound_device(subject: AuthenticatedSubject) -> str:
    if subject.device_id is None:
        raise HTTPException(
            status_code=403,
            detail="AI relay requires a device-bound authenticated session",
        )
    return subject.device_id


async def _trusted_device(
    devices: DeviceRepository,
    *,
    account_id: str,
    device_id: str,
) -> DeviceRecord:
    try:
        device = await devices.get_for_account(account_id, device_id)
    except DeviceNotFound as exc:
        raise HTTPException(status_code=404, detail="Device not found") from exc
    if device.trust_state != DeviceTrustState.TRUSTED or device.revoked_at is not None:
        raise HTTPException(status_code=409, detail="AI relay device is not trusted")
    return device


def _require_account_and_source(
    envelope: AiJobEnvelope,
    *,
    subject: AuthenticatedSubject,
    source_device_id: str,
) -> None:
    if envelope.account_id != subject.account_id:
        raise HTTPException(status_code=403, detail="AI relay account mismatch")
    if envelope.source_device_id != source_device_id:
        raise HTTPException(status_code=403, detail="AI relay source device mismatch")


@router.post("/jobs", response_model=AiJobEnvelope)
async def submit_job(
    envelope: AiJobEnvelope,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
    store: AiRelayStore = Depends(get_ai_relay_store),
) -> AiJobEnvelope:
    source_device_id = _require_bound_device(subject)
    _require_account_and_source(
        envelope,
        subject=subject,
        source_device_id=source_device_id,
    )
    if envelope.message_type != AiJobMessageType.REQUEST or envelope.correlation_id is not None:
        raise HTTPException(status_code=422, detail="AI relay jobs must be request envelopes")
    if envelope.target_device_id == source_device_id:
        raise HTTPException(status_code=409, detail="AI relay target must be another device")
    if envelope.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(status_code=409, detail="AI relay job is already expired")

    await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=source_device_id,
    )
    target = await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=envelope.target_device_id,
    )
    if DeviceCapability.LOCAL_AI not in target.capability_report.capabilities:
        raise HTTPException(status_code=409, detail="Target device has no local AI capability")
    try:
        return await store.submit_request(envelope)
    except (AiRelayConflict, ValueError) as exc:
        raise HTTPException(status_code=409, detail="AI relay request conflicts with existing job") from exc


@router.get("/jobs/next", response_model=AiJobEnvelope | None)
async def poll_next_job(
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
    store: AiRelayStore = Depends(get_ai_relay_store),
) -> AiJobEnvelope | None:
    target_device_id = _require_bound_device(subject)
    target = await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=target_device_id,
    )
    if DeviceCapability.LOCAL_AI not in target.capability_report.capabilities:
        raise HTTPException(status_code=409, detail="Current device has no local AI capability")
    return await store.next_for_target(
        account_id=subject.account_id,
        target_device_id=target_device_id,
        now=datetime.now(timezone.utc),
    )


@router.post("/results", response_model=AiJobEnvelope)
async def submit_result(
    envelope: AiJobEnvelope,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
    store: AiRelayStore = Depends(get_ai_relay_store),
) -> AiJobEnvelope:
    source_device_id = _require_bound_device(subject)
    _require_account_and_source(
        envelope,
        subject=subject,
        source_device_id=source_device_id,
    )
    if envelope.message_type != AiJobMessageType.RESULT or envelope.correlation_id is None:
        raise HTTPException(status_code=422, detail="AI relay results must reference a request")

    await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=source_device_id,
    )
    await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=envelope.target_device_id,
    )
    request = await store.get_request(
        account_id=subject.account_id,
        job_id=envelope.correlation_id,
    )
    if request is None:
        raise HTTPException(status_code=404, detail="AI relay request not found")
    if request.target_device_id != source_device_id:
        raise HTTPException(status_code=403, detail="Only the request target may submit its result")
    if request.source_device_id != envelope.target_device_id:
        raise HTTPException(status_code=409, detail="AI relay result requester mismatch")
    if request.idempotency_key != envelope.idempotency_key:
        raise HTTPException(status_code=409, detail="AI relay result idempotency mismatch")
    if envelope.expires_at != request.expires_at:
        raise HTTPException(status_code=409, detail="AI relay result expiry mismatch")
    try:
        return await store.submit_result(request=request, result=envelope)
    except (AiRelayConflict, ValueError) as exc:
        raise HTTPException(status_code=409, detail="AI relay result conflicts with existing job") from exc


@router.get("/jobs/{job_id}/result", response_model=AiJobEnvelope | None)
async def read_result(
    job_id: str,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
    store: AiRelayStore = Depends(get_ai_relay_store),
) -> AiJobEnvelope | None:
    requester_device_id = _require_bound_device(subject)
    await _trusted_device(
        devices,
        account_id=subject.account_id,
        device_id=requester_device_id,
    )
    request = await store.get_request(account_id=subject.account_id, job_id=job_id)
    if request is None:
        raise HTTPException(status_code=404, detail="AI relay request not found")
    if request.source_device_id != requester_device_id:
        raise HTTPException(status_code=403, detail="Only the requester may read this AI result")
    return await store.result_for_request(
        account_id=subject.account_id,
        request_job_id=job_id,
        requester_device_id=requester_device_id,
        now=datetime.now(timezone.utc),
    )
