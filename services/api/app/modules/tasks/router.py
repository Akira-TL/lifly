from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Task, TaskReminderStrategy
from app.modules.tasks.service import (
    DEFAULT_LOCAL_USER_ID,
    complete_task_record,
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


def _parse_datetime(value: object) -> datetime | None:
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    return None


def _strategy_data(strategy: TaskReminderStrategy) -> dict:
    return {
        "id": strategy.id,
        "task_id": strategy.task_id,
        "warning_level": strategy.warning_level,
        "warning_reason": strategy.warning_reason,
        "preparation_window_days": strategy.preparation_window_days,
        "ai_suggested_remind_at": strategy.ai_suggested_remind_at.isoformat()
        if strategy.ai_suggested_remind_at
        else None,
        "strategy_status": strategy.strategy_status,
        "source": strategy.source,
        "confirmed_at": strategy.confirmed_at.isoformat() if strategy.confirmed_at else None,
        "dismissed_at": strategy.dismissed_at.isoformat() if strategy.dismissed_at else None,
        "created_at": strategy.created_at.isoformat() if strategy.created_at else None,
        "updated_at": strategy.updated_at.isoformat() if strategy.updated_at else None,
    }


async def _load_task(db: AsyncSession, task_id: str) -> Task:
    result = await db.execute(
        select(Task).where(Task.id == task_id, Task.user_id == DEFAULT_LOCAL_USER_ID)
    )
    task = result.scalar_one_or_none()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


async def _load_strategy(
    db: AsyncSession,
    task_id: str,
    strategy_id: str | None = None,
) -> TaskReminderStrategy | None:
    query = select(TaskReminderStrategy).where(
        TaskReminderStrategy.user_id == DEFAULT_LOCAL_USER_ID,
        TaskReminderStrategy.task_id == task_id,
        TaskReminderStrategy.strategy_status != "dismissed",
    )
    if strategy_id:
        query = query.where(TaskReminderStrategy.id == strategy_id)
    query = query.order_by(TaskReminderStrategy.updated_at.desc())
    result = await db.execute(query)
    return result.scalar_one_or_none()


async def _upsert_strategy(
    db: AsyncSession,
    task_id: str,
    data: dict,
    status: str,
) -> TaskReminderStrategy:
    await _load_task(db, task_id)
    strategy_id = data.get("strategy_id") or data.get("id")
    strategy = await _load_strategy(db, task_id, str(strategy_id)) if strategy_id else None
    if strategy is None:
        strategy = TaskReminderStrategy(
            user_id=DEFAULT_LOCAL_USER_ID,
            task_id=task_id,
            warning_level=str(data.get("warning_level") or "normal"),
            warning_reason=data.get("warning_reason"),
            preparation_window_days=data.get("preparation_window_days"),
            ai_suggested_remind_at=_parse_datetime(data.get("ai_suggested_remind_at")),
            source=str(data.get("source") or "user"),
        )
        db.add(strategy)
    strategy.strategy_status = status
    if status == "confirmed":
        strategy.confirmed_at = datetime.now(timezone.utc)
        if strategy.ai_suggested_remind_at:
            task = await _load_task(db, task_id)
            task.remind_at = strategy.ai_suggested_remind_at
            task.revision += 1
    elif status == "dismissed":
        strategy.dismissed_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(strategy)
    return strategy


def _task_matches_group(task: Task, group: str, now: datetime) -> bool:
    if group == "all":
        return True
    if task.task_status not in {"todo", "doing"}:
        return False
    due_at = task.due_at
    if group == "today":
        return due_at is not None and due_at.date() == now.date()
    if group == "urgent":
        return task.priority == "urgent" or (due_at is not None and due_at < now)
    if group == "warning":
        return task.priority == "high" or (
            due_at is not None and now <= due_at <= now + timedelta(days=3)
        )
    return True


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
    group: str = Query(default="all"),
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
    if group == "urgent":
        now = datetime.now(timezone.utc)
        critical_strategy_ids = select(TaskReminderStrategy.task_id).where(
            TaskReminderStrategy.user_id == DEFAULT_LOCAL_USER_ID,
            TaskReminderStrategy.strategy_status != "dismissed",
            TaskReminderStrategy.warning_level == "critical",
        )
        query = query.where(
            Task.task_status.in_(["todo", "doing"]),
            (Task.priority == "urgent") | (Task.due_at < now) | Task.id.in_(critical_strategy_ids),
        )
    elif group == "warning":
        now = datetime.now(timezone.utc)
        warning_strategy_ids = select(TaskReminderStrategy.task_id).where(
            TaskReminderStrategy.user_id == DEFAULT_LOCAL_USER_ID,
            TaskReminderStrategy.strategy_status != "dismissed",
            TaskReminderStrategy.warning_level == "warning",
        )
        query = query.where(
            Task.task_status.in_(["todo", "doing"]),
            (Task.priority == "high")
            | Task.due_at.between(now, now + timedelta(days=3))
            | Task.id.in_(warning_strategy_ids),
        )
    elif group == "today":
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


@router.get("/{task_id}/reminder-strategy", response_model=ApiResponse)
async def get_task_reminder_strategy(task_id: str, db: AsyncSession = Depends(get_db)):
    await _load_task(db, task_id)
    strategy = await _load_strategy(db, task_id)
    return ApiResponse(data=None if strategy is None else _strategy_data(strategy))


@router.post("/{task_id}/reminder-strategy/confirm", response_model=ApiResponse)
async def confirm_task_reminder_strategy(
    task_id: str,
    data: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
):
    strategy = await _upsert_strategy(db, task_id, data, "confirmed")
    return ApiResponse(data=_strategy_data(strategy))


@router.post("/{task_id}/reminder-strategy/dismiss", response_model=ApiResponse)
async def dismiss_task_reminder_strategy(
    task_id: str,
    data: dict = Body(default_factory=dict),
    db: AsyncSession = Depends(get_db),
):
    strategy = await _upsert_strategy(db, task_id, data, "dismissed")
    return ApiResponse(data=_strategy_data(strategy))


@router.get("/{task_id}", response_model=ApiResponse)
async def get_task(task_id: str, db: AsyncSession = Depends(get_db)):
    task = await _load_task(db, task_id)
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
    task = await complete_task_record(
        db,
        task_id=task_id,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="user",
        source_channel="api",
    )
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

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
