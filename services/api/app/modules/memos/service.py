from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditLog, Memo
from app.modules.memos.classification_engine import generate_memo_classifications
from app.schemas.common import MemoCreate, MemoResponse, json_serialize


DEFAULT_LOCAL_USER_ID = "local-dev"


def memo_to_response(memo: Memo) -> MemoResponse:
    return MemoResponse(
        id=memo.id,
        user_id=memo.user_id,
        type=memo.type,
        title=memo.title,
        content_markdown=memo.content_markdown,
        tags=memo.tags,
        mood=memo.mood,
        status=memo.status,
        created_at=memo.created_at,
        updated_at=memo.updated_at,
    )


async def write_memo_audit(
    db: AsyncSession,
    *,
    user_id: str,
    actor_type: str,
    action: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> None:
    log = AuditLog(
        user_id=user_id,
        actor_type=actor_type,
        action=action,
        entity_type="memo",
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
    )
    db.add(log)


async def create_memo_record(
    db: AsyncSession,
    data: MemoCreate,
    *,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
    request_id: str | None = None,
) -> Memo:
    memo = Memo(
        user_id=user_id,
        type=data.type,
        title=data.title,
        content_markdown=data.content_markdown,
        tags=data.tags,
        mood=data.mood,
        source_capture_id=data.source_capture_id,
        source=data.source or source_channel,
    )
    db.add(memo)
    await db.flush()

    await write_memo_audit(
        db,
        user_id=user_id,
        actor_type=actor_type,
        action="create",
        entity_id=memo.id,
        after=json_serialize(memo_to_response(memo).model_dump()),
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
        request_id=request_id,
    )
    await generate_memo_classifications(db, memo)

    return memo
