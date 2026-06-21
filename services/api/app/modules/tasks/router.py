from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Task, AuditLog
from app.schemas.common import (
    TaskCreate,
    TaskUpdate,
    TaskResponse,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


def _task_to_response(task: Task) -> TaskResponse:
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


async def _write_audit(
    db: AsyncSession,
    user_id: str,
    action: str,
    entity_type: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
):
    log = AuditLog(
        user_id=user_id,
        actor_type="user",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel="api",
    )
    db.add(log)


@router.post("", response_model=ApiResponse)
async def create_task(data: TaskCreate, db: AsyncSession = Depends(get_db)):
    task = Task(
        user_id="local-dev",
        title=data.title,
        description=data.description,
        due_at=data.due_at,
        remind_at=data.remind_at,
        priority=data.priority,
        source_capture_id=data.source_capture_id,
        source=data.source or "manual",
    )
    db.add(task)
    await db.flush()
    await _write_audit(db, "local-dev", "create", "task", task.id, after=json_serialize(_task_to_response(task).model_dump()))
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=_task_to_response(task).model_dump())


@router.get("", response_model=ApiResponse)
async def list_tasks(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    task_status: str | None = Query(default=None),
    priority: str | None = Query(default=None),
    overdue: bool = Query(default=False),
    today: bool = Query(default=False),
    db: AsyncSession = Depends(get_db),
):
    query = select(Task).where(Task.user_id == "local-dev", Task.status == "active")

    if task_status:
        query = query.where(Task.task_status == task_status)
    if priority:
        query = query.where(Task.priority == priority)
    if overdue:
        now = datetime.now(timezone.utc)
        query = query.where(
            Task.due_at < now,
            Task.task_status.in_(["todo", "doing"]),
        )
    if today:
        now = datetime.now(timezone.utc)
        start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        end = start.replace(hour=23, minute=59, second=59)
        query = query.where(Task.due_at.between(start, end))

    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query)

    query = query.order_by(Task.created_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    tasks = result.scalars().all()

    return ApiResponse(
        data=PaginatedResponse(
            total=total or 0, limit=limit, offset=offset,
            items=[_task_to_response(t).model_dump() for t in tasks],
        ).model_dump()
    )


@router.get("/{task_id}", response_model=ApiResponse)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == "local-dev")
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return ApiResponse(data=_task_to_response(task).model_dump())


@router.put("/{task_id}", response_model=ApiResponse)
async def update_task(task_id: str, data: TaskUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == "local-dev")
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = _task_to_response(task).model_dump()
    update_data = data.model_dump(exclude_unset=True)

    # Handle completion
    if update_data.get("task_status") == "done" and task.task_status != "done":
        update_data["completed_at"] = datetime.now(timezone.utc)
    elif update_data.get("task_status") and update_data["task_status"] != "done":
        update_data["completed_at"] = None

    for key, value in update_data.items():
        setattr(task, key, value)
    task.revision += 1

    await _write_audit(db, "local-dev", "update", "task", task_id, before=json_serialize(before), after=json_serialize(_task_to_response(task).model_dump()))
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=_task_to_response(task).model_dump())


@router.post("/{task_id}/complete", response_model=ApiResponse)
async def complete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == "local-dev")
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = _task_to_response(task).model_dump()
    task.task_status = "done"
    task.completed_at = datetime.now(timezone.utc)
    task.revision += 1

    await _write_audit(db, "local-dev", "complete", "task", task_id, before=json_serialize(before), after=json_serialize(_task_to_response(task).model_dump()))
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=_task_to_response(task).model_dump())


@router.delete("/{task_id}", response_model=ApiResponse)
async def delete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == "local-dev")
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = _task_to_response(task).model_dump()
    task.status = "user_trashed"
    task.deleted_at = datetime.now(timezone.utc)
    task.revision += 1

    await _write_audit(db, "local-dev", "trash", "task", task_id, before=json_serialize(before))
    await db.commit()
    return ApiResponse(data={"id": task_id, "status": "user_trashed"})
