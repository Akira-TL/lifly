from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import AuthenticatedSubject, get_authenticated_subject
from app.modules.sync.encrypted_service import apply_encrypted_sync_push
from app.modules.sync.schemas import (
    EncryptedSyncPushRequest,
    PowerSyncCredentialsResponse,
    SyncPushRequest,
)
from app.modules.sync.service import issue_powersync_credentials
from app.schemas.common import ApiResponse

router = APIRouter()


@router.get("/credentials", response_model=ApiResponse)
async def get_credentials(
    subject: AuthenticatedSubject = Depends(get_authenticated_subject),
) -> ApiResponse:
    try:
        credentials: PowerSyncCredentialsResponse = issue_powersync_credentials(subject)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(error),
        ) from error
    return ApiResponse(data=credentials.model_dump())


@router.post("/encrypted", response_model=ApiResponse)
async def push_encrypted_changes(
    request: EncryptedSyncPushRequest,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_authenticated_subject),
) -> ApiResponse:
    try:
        result = await apply_encrypted_sync_push(db, subject, request)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(error),
        ) from error
    except PermissionError as error:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(error),
        ) from error
    await db.commit()
    return ApiResponse(data=result.model_dump())


@router.post("/push", response_model=ApiResponse, deprecated=True)
async def reject_legacy_plaintext_push(
    request: SyncPushRequest,
    subject: AuthenticatedSubject = Depends(get_authenticated_subject),
) -> ApiResponse:
    del request, subject
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail=(
            "Plaintext cloud sync is disabled in v0.9.0. "
            "Migrate local rows through EncryptedSyncStore and /sync/encrypted."
        ),
    )
