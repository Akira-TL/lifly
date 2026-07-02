from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.sync.schemas import PowerSyncCredentialsResponse, SyncPushRequest, SyncPushResponse
from app.modules.sync.service import apply_sync_push, issue_powersync_credentials
from app.schemas.common import ApiResponse

router = APIRouter()


@router.get("/credentials", response_model=ApiResponse)
async def get_credentials() -> ApiResponse:
    credentials: PowerSyncCredentialsResponse = issue_powersync_credentials()
    return ApiResponse(data=credentials.model_dump())


@router.post("/push", response_model=ApiResponse)
async def push_changes(
    request: SyncPushRequest,
    db: AsyncSession = Depends(get_db),
) -> ApiResponse:
    result: SyncPushResponse = await apply_sync_push(db, request)
    await db.commit()
    return ApiResponse(data=result.model_dump())
