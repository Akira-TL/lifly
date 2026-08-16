from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import AuthenticatedSubject
from app.modules.auth.sessions import SessionStore, get_active_subject, get_session_registry
from app.modules.devices.contracts import (
    DeviceDescriptor,
    DeviceEnrollmentRequest,
    DeviceHeartbeatRequest,
    DeviceListResponse,
    DeviceRevokeResponse,
    DeviceUpdateRequest,
)
from app.modules.devices.repository import (
    DeviceNotFound,
    DeviceNotTrusted,
    DeviceOwnershipConflict,
    DeviceRecord,
    DeviceRepository,
    get_device_repository,
)

router = APIRouter()


def _descriptor(device: DeviceRecord) -> DeviceDescriptor:
    return DeviceDescriptor(
        device_id=device.device_id,
        account_id=device.account_id,
        display_name=device.display_name,
        platform=device.platform,
        public_key=device.public_key,
        trust_state=device.trust_state,
        capability_report=device.capability_report,
        is_default_compute_node=device.is_default_compute_node,
        last_seen_at=device.last_seen_at,
        revoked_at=device.revoked_at,
        key_version=device.key_version,
        protocol_version=device.protocol_version,
    )


def _not_found(exc: DeviceNotFound) -> HTTPException:
    return HTTPException(status_code=404, detail="Device not found")


@router.get("", response_model=DeviceListResponse)
async def list_devices(
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
) -> DeviceListResponse:
    records = await devices.list_for_account(subject.account_id)
    return DeviceListResponse(devices=[_descriptor(item) for item in records])


@router.post("/register", response_model=DeviceDescriptor)
async def register_device(
    request: DeviceEnrollmentRequest,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
) -> DeviceDescriptor:
    if subject.device_id is not None and subject.device_id != request.device_id:
        raise HTTPException(
            status_code=403,
            detail="A device-bound session can only refresh its own enrollment",
        )
    try:
        device = await devices.register_trusted(
            account_id=subject.account_id,
            device_id=request.device_id,
            display_name=request.display_name,
            platform=request.platform,
            public_key=request.public_key,
            capability_report=request.capability_report,
            make_default_compute_node=request.make_default_compute_node,
        )
    except DeviceOwnershipConflict as exc:
        raise HTTPException(status_code=409, detail="Device id is unavailable") from exc
    return _descriptor(device)


@router.put("/{device_id}", response_model=DeviceDescriptor)
async def update_device(
    device_id: str,
    request: DeviceUpdateRequest,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
) -> DeviceDescriptor:
    try:
        if request.display_name is None:
            device = await devices.get_for_account(subject.account_id, device_id)
        else:
            device = await devices.rename(
                account_id=subject.account_id,
                device_id=device_id,
                display_name=request.display_name,
            )
    except DeviceNotFound as exc:
        raise _not_found(exc) from exc
    return _descriptor(device)


@router.post("/{device_id}/heartbeat", response_model=DeviceDescriptor)
async def heartbeat_device(
    device_id: str,
    request: DeviceHeartbeatRequest,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
) -> DeviceDescriptor:
    if subject.device_id != device_id:
        raise HTTPException(status_code=403, detail="Heartbeat must come from that device")
    try:
        device = await devices.heartbeat(
            account_id=subject.account_id,
            device_id=device_id,
            capability_report=request.capability_report,
        )
    except DeviceNotFound as exc:
        raise _not_found(exc) from exc
    except DeviceNotTrusted as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return _descriptor(device)


@router.put("/{device_id}/default-compute-node", response_model=DeviceDescriptor)
async def set_default_compute_node(
    device_id: str,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
) -> DeviceDescriptor:
    try:
        device = await devices.set_default_compute_node(
            account_id=subject.account_id,
            device_id=device_id,
        )
    except DeviceNotFound as exc:
        raise _not_found(exc) from exc
    except DeviceNotTrusted as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return _descriptor(device)


@router.post("/{device_id}/revoke", response_model=DeviceRevokeResponse)
async def revoke_device(
    device_id: str,
    subject: AuthenticatedSubject = Depends(get_active_subject),
    devices: DeviceRepository = Depends(get_device_repository),
    sessions: SessionStore = Depends(get_session_registry),
) -> DeviceRevokeResponse:
    try:
        device = await devices.revoke(
            account_id=subject.account_id,
            device_id=device_id,
        )
    except DeviceNotFound as exc:
        raise _not_found(exc) from exc
    revoked_sessions = await sessions.revoke_device(
        account_id=subject.account_id,
        device_id=device_id,
    )
    return DeviceRevokeResponse(
        device=_descriptor(device),
        revoked_sessions=revoked_sessions,
    )
