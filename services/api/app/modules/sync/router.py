from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.modules.sync.schemas import SyncPushRequest, SyncPushResponse
from app.modules.sync.service import apply_sync_push
from app.schemas.common import ApiResponse

router = APIRouter()


@router.post("/push", response_model=ApiResponse)
async def push_changes(
    request: SyncPushRequest,
    db: AsyncSession = Depends(get_db),
) -> ApiResponse:
    result: SyncPushResponse = await apply_sync_push(db, request)
    await db.commit()
    return ApiResponse(data=result.model_dump())
