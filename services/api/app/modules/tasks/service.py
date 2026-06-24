from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditLog, Task
from app.schemas.common import TaskCreate, TaskResponse, json_serialize

DEFAULT_LOCAL_USER_ID = "local-dev"


def task_to_response(task: Task) -> TaskResponse:
    return TaskResponse(
        id=task.id,
        user_id=task.user_id,
        title=task.title,
        description=task.description,
        due_at=task.due_at,
        remind_at=task.remind_at,
        priority=task.priority,
        task_status=task.task_status,
        status=task.status,
        completed_at=task.completed_at,
        created_at=task.created_at,
        updated_at=task.updated_at,
    )


def task_to_dict(task: Task) -> dict:
    return json_serialize(task_to_response(task).model_dump())


async def write_task_audit(
    db: AsyncSession,
    *,
    user_id: str,
    action: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
) -> AuditLog:
    log = AuditLog(
        user_id=user_id,
        actor_type=actor_type,
        action=action,
        entity_type="task",
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
    )
    db.add(log)
    return log


async def create_task_record(
    db: AsyncSession,
    data: TaskCreate,
    *,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
) -> Task:
    task = Task(
        user_id=user_id,
        title=data.title,
        description=data.description,
        due_at=data.due_at,
        remind_at=data.remind_at,
        priority=data.priority,
        source_capture_id=data.source_capture_id,
        source=data.source or source_channel,
    )
    db.add(task)
    await db.flush()

    await write_task_audit(
        db,
        user_id=user_id,
        action="create",
        entity_id=task.id,
        after=task_to_dict(task),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
    )
    return task


async def complete_task_record(
    db: AsyncSession,
    *,
    task_id: str,
    user_id: str = DEFAULT_LOCAL_USER_ID,
    actor_type: str = "user",
    source_channel: str = "api",
    tool_name: str | None = None,
    source_text: str | None = None,
) -> Task | None:
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == user_id, Task.status == "active")
    )
    task = result.scalar_one_or_none()
    if not task:
        return None

    before = task_to_dict(task)
    completed_at = datetime.now(timezone.utc)
    task.task_status = "done"
    task.completed_at = completed_at
    task.updated_at = completed_at
    task.revision += 1
    await db.flush()
    await db.refresh(task)

    await write_task_audit(
        db,
        user_id=user_id,
        action="complete",
        entity_id=task_id,
        before=before,
        after=task_to_dict(task),
        actor_type=actor_type,
        source_channel=source_channel,
        tool_name=tool_name,
        source_text=source_text,
    )
    return task
