from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Task
from app.modules.tasks.service import (
    DEFAULT_LOCAL_USER_ID,
    create_task_record,
    task_to_response,
    write_task_audit,
)
from app.schemas.common import (
    TaskCreate,
    TaskUpdate,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


@router.post("", response_model=ApiResponse)
async def create_task(data: TaskCreate, db: AsyncSession = Depends(get_db)):
    task = await create_task_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=task_to_response(task).model_dump())


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
    query = select(Task).where(Task.user_id == DEFAULT_LOCAL_USER_ID, Task.status == "active")

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
            total=total or 0,
            limit=limit,
            offset=offset,
            items=[task_to_response(t).model_dump() for t in tasks],
        ).model_dump()
    )


@router.get("/{task_id}", response_model=ApiResponse)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return ApiResponse(data=task_to_response(task).model_dump())


@router.put("/{task_id}", response_model=ApiResponse)
async def update_task(task_id: str, data: TaskUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = task_to_response(task).model_dump()
    update_data = data.model_dump(exclude_unset=True)

    if update_data.get("task_status") == "done" and task.task_status != "done":
        update_data["completed_at"] = datetime.now(timezone.utc)
    elif update_data.get("task_status") and update_data["task_status"] != "done":
        update_data["completed_at"] = None

    for key, value in update_data.items():
        setattr(task, key, value)
    task.revision += 1

    await write_task_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        action="update",
        entity_id=task_id,
        before=json_serialize(before),
        after=json_serialize(task_to_response(task).model_dump()),
    )
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=task_to_response(task).model_dump())


@router.post("/{task_id}/complete", response_model=ApiResponse)
async def complete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = task_to_response(task).model_dump()
    task.task_status = "done"
    task.completed_at = datetime.now(timezone.utc)
    task.revision += 1

    await write_task_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        action="complete",
        entity_id=task_id,
        before=json_serialize(before),
        after=json_serialize(task_to_response(task).model_dump()),
    )
    await db.commit()
    await db.refresh(task)
    return ApiResponse(data=task_to_response(task).model_dump())


@router.delete("/{task_id}", response_model=ApiResponse)
async def delete_task(task_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    before = task_to_response(task).model_dump()
    task.status = "user_trashed"
    task.deleted_at = datetime.now(timezone.utc)
    task.revision += 1

    await write_task_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        action="trash",
        entity_id=task_id,
        before=json_serialize(before),
    )
    await db.commit()
    return ApiResponse(data={"id": task_id, "status": "user_trashed"})
