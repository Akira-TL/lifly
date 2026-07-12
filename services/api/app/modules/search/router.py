from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import case, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.db.models import (
    Asset,
    ImportBatch,
    LedgerBudget,
    LedgerCategory,
    LedgerTransaction,
    Memo,
    MemoClassification,
    TagMetadata,
    Task,
    TaskReminderStrategy,
)
from app.schemas.common import ApiResponse, TagMetadataUpsert

router = APIRouter()

DEFAULT_LOCAL_USER_ID = "local-dev"
HOME_OVERVIEW_SCHEMA_VERSION = "home_overview.v1"


def _week_range() -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=now.weekday())
    return start.replace(hour=0, minute=0, second=0, microsecond=0), now


def _month_range() -> tuple[datetime, datetime]:
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0), now


def _to_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _iso(value: datetime | None) -> str | None:
    normalized = _to_utc(value)
    return normalized.isoformat() if normalized else None


def _same_utc_day(left: datetime | None, right: datetime) -> bool:
    normalized = _to_utc(left)
    if normalized is None:
        return False
    baseline = _to_utc(right) or right
    return normalized.date() == baseline.date()


def _build_attention_items(
    tasks: list[Task],
    strategies: dict[str, TaskReminderStrategy],
    now: datetime,
) -> list[dict[str, object | None]]:
    todo_tasks = [task for task in tasks if task.task_status == "todo"]
    overdue_tasks = [
        task for task in todo_tasks if _to_utc(task.due_at) is not None and _to_utc(task.due_at) < now
    ]
    today_tasks = [task for task in todo_tasks if _same_utc_day(task.due_at, now)]

    items: list[dict[str, object | None]] = []
    for task in overdue_tasks[:3]:
        strategy = strategies.get(task.id)
        items.append({
            "id": f"overdue_task_{task.id}",
            "type": "task_overdue",
            "level": "critical",
            "title": task.title,
            "description": strategy.warning_reason if strategy else "任务已逾期",
            "entity_type": "task",
            "entity_id": task.id,
            "occurred_at": _iso(task.due_at),
        })

    overdue_ids = {task.id for task in overdue_tasks}
    for task in today_tasks:
        if len(items) >= 3:
            break
        if task.id in overdue_ids:
            continue
        strategy = strategies.get(task.id)
        level = _task_attention_level(task, strategy)
        items.append({
            "id": f"today_task_{task.id}",
            "type": "task_warning_strategy" if strategy else "task_due_today",
            "level": level,
            "title": task.title,
            "description": strategy.warning_reason if strategy else "今天截止",
            "entity_type": "task",
            "entity_id": task.id,
            "occurred_at": _iso(task.due_at or (strategy.ai_suggested_remind_at if strategy else None)),
        })

    return items


def _task_attention_level(task: Task, strategy: TaskReminderStrategy | None) -> str:
    if strategy and strategy.warning_level == "critical":
        return "critical"
    if strategy and strategy.warning_level == "warning":
        return "warning"
    return "warning" if task.priority == "high" else "normal"


def _build_daily_trend(transactions: list[LedgerTransaction], now: datetime) -> list[dict[str, object]]:
    week_start = (now - timedelta(days=now.weekday())).replace(
        hour=0,
        minute=0,
        second=0,
        microsecond=0,
    )
    trend: list[dict[str, object]] = []
    for index in range(7):
        day = week_start + timedelta(days=index)
        total = sum(
            float(tx.amount)
            for tx in transactions
            if tx.direction == "expense" and _same_utc_day(tx.occurred_at, day)
        )
        trend.append({"day": day.date().isoformat(), "total": round(total, 2)})
    return trend


def _build_recent_activity(
    memos: list[Memo],
    tasks: list[Task],
    transactions: list[LedgerTransaction],
) -> list[dict[str, object | None]]:
    items: list[dict[str, object | None]] = []
    for memo in memos:
        content = (memo.content_markdown or "").strip()
        items.append({
            "id": f"memo_{memo.id}",
            "entity_type": "memo",
            "entity_id": memo.id,
            "title": memo.title or "无标题备忘",
            "subtitle": content or None,
            "occurred_at": _iso(memo.updated_at),
            "amount": None,
            "direction": None,
        })

    for task in tasks:
        items.append({
            "id": f"task_{task.id}",
            "entity_type": "task",
            "entity_id": task.id,
            "title": task.title,
            "subtitle": "已完成" if task.task_status == "done" else "待处理",
            "occurred_at": _iso(task.due_at or task.updated_at),
            "amount": None,
            "direction": None,
        })

    for tx in transactions:
        items.append({
            "id": f"ledger_transaction_{tx.id}",
            "entity_type": "ledger_transaction",
            "entity_id": tx.id,
            "title": tx.merchant or "账单记录",
            "subtitle": tx.note,
            "occurred_at": _iso(tx.occurred_at),
            "amount": float(tx.amount),
            "direction": tx.direction,
        })

    items.sort(key=lambda item: str(item.get("occurred_at") or ""), reverse=True)
    return items[:10]


async def _active_memo_count(db: AsyncSession, user_id: str) -> int:
    return int(await db.scalar(
        select(func.count()).select_from(
            select(Memo).where(Memo.user_id == user_id, Memo.status == "active").subquery()
        )
    ) or 0)


async def _active_tasks(db: AsyncSession, user_id: str, limit: int = 100) -> list[Task]:
    result = await db.execute(
        select(Task)
        .where(Task.user_id == user_id, Task.status == "active")
        .order_by(Task.updated_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def _active_memos(db: AsyncSession, user_id: str, limit: int = 20) -> list[Memo]:
    result = await db.execute(
        select(Memo)
        .where(Memo.user_id == user_id, Memo.status == "active")
        .order_by(Memo.updated_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def _active_transactions(
    db: AsyncSession,
    user_id: str,
    limit: int = 100,
) -> list[LedgerTransaction]:
    result = await db.execute(
        select(LedgerTransaction)
        .where(LedgerTransaction.user_id == user_id, LedgerTransaction.status == "active")
        .order_by(LedgerTransaction.occurred_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


async def _task_strategy_map(db: AsyncSession, user_id: str) -> dict[str, TaskReminderStrategy]:
    result = await db.execute(
        select(TaskReminderStrategy)
        .where(
            TaskReminderStrategy.user_id == user_id,
            TaskReminderStrategy.strategy_status != "dismissed",
        )
        .order_by(TaskReminderStrategy.updated_at.desc())
    )
    strategies: dict[str, TaskReminderStrategy] = {}
    for strategy in result.scalars().all():
        strategies.setdefault(strategy.task_id, strategy)
    return strategies


async def _monthly_budget(
    db: AsyncSession,
    user_id: str,
    period_key: str,
) -> LedgerBudget | None:
    return await db.scalar(
        select(LedgerBudget)
        .where(
            LedgerBudget.user_id == user_id,
            LedgerBudget.status == "active",
            LedgerBudget.period_type == "month",
            LedgerBudget.period_key == period_key,
            LedgerBudget.category_id.is_(None),
        )
        .order_by(LedgerBudget.updated_at.desc())
    )


async def _category_breakdown(
    db: AsyncSession,
    user_id: str,
    month_start: datetime,
    month_end: datetime,
) -> list[dict[str, object]]:
    result = await db.execute(
        select(
            LedgerTransaction.category_id.label("category_id"),
            LedgerCategory.name.label("category_name"),
            LedgerCategory.color.label("color_token"),
            LedgerCategory.icon.label("icon_token"),
            func.sum(LedgerTransaction.amount).label("amount"),
            func.count().label("transaction_count"),
        )
        .select_from(LedgerTransaction)
        .join(LedgerCategory, LedgerCategory.id == LedgerTransaction.category_id, isouter=True)
        .where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
            LedgerTransaction.direction == "expense",
            LedgerTransaction.occurred_at >= month_start,
            LedgerTransaction.occurred_at < month_end,
        )
        .group_by(
            LedgerTransaction.category_id,
            LedgerCategory.name,
            LedgerCategory.color,
            LedgerCategory.icon,
        )
        .order_by(func.sum(LedgerTransaction.amount).desc())
    )
    rows = result.all()
    total = sum(float(row.amount or 0) for row in rows)
    return [{
        "category_id": row.category_id or "uncategorized",
        "category_name": row.category_name or "未分类",
        "direction": "expense",
        "amount": round(float(row.amount or 0), 2),
        "ratio": float(row.amount or 0) / total if total > 0 else 0,
        "transaction_count": int(row.transaction_count or 0),
        "color_token": row.color_token,
        "icon_token": row.icon_token,
    } for row in rows]


async def _sync_summary(
    db: AsyncSession,
    user_id: str,
) -> dict[str, object]:
    result = await db.execute(
        select(Asset.sync_status, func.count().label("count"))
        .where(Asset.user_id == user_id, Asset.status == "active")
        .group_by(Asset.sync_status)
    )
    counts = {str(row.sync_status): int(row.count or 0) for row in result.all()}
    pending_count = counts.get("pending", 0)
    failed_count = counts.get("failed", 0)
    synced_count = counts.get("synced", 0)
    powersync_configured = bool(settings.powersync_url.strip())

    if failed_count > 0:
        status = "error"
    elif pending_count > 0:
        status = "pending"
    elif powersync_configured:
        status = "ready"
    else:
        status = "not_configured"

    return {
        "status": status,
        "mode": "server",
        "powersync_configured": powersync_configured,
        "pending_asset_count": pending_count,
        "failed_asset_count": failed_count,
        "synced_asset_count": synced_count,
    }


async def _import_summary(
    db: AsyncSession,
    user_id: str,
) -> dict[str, object]:
    batch = await db.scalar(
        select(ImportBatch)
        .where(ImportBatch.user_id == user_id)
        .order_by(ImportBatch.created_at.desc())
        .limit(1)
    )
    if batch is None:
        return {"status": "idle"}

    return {
        "status": batch.status,
        "latest_batch_id": batch.id,
        "source_provider": batch.source_provider,
        "filename": batch.filename,
        "total_rows": batch.total_rows or 0,
        "valid_rows": batch.valid_rows or 0,
        "duplicate_rows": batch.duplicate_rows or 0,
        "created_at": _iso(batch.created_at),
        "committed_at": _iso(batch.committed_at),
        "rolled_back_at": _iso(batch.rolled_back_at),
    }


def _settings_summary() -> dict[str, object]:
    database_configured = bool(settings.database_url.strip())
    powersync_configured = bool(settings.powersync_url.strip())
    object_storage_configured = bool(
        settings.minio_endpoint.strip() and settings.minio_bucket.strip()
    )
    configured = (
        database_configured and powersync_configured and object_storage_configured
    )
    return {
        "status": "ok" if configured else "attention",
        "mode": "server",
        "data_mode": "api",
        "local_core_available": False,
        "timezone": "UTC",
        "database_configured": database_configured,
        "powersync_configured": powersync_configured,
        "object_storage_configured": object_storage_configured,
    }


def _finance_insights(
    *,
    budget_state: str,
    budget_progress: float | None,
) -> list[dict[str, object]]:
    if budget_state == "not_configured":
        return [{
            "id": "budget_not_configured",
            "type": "budget",
            "level": "info",
            "title": "未设置预算",
            "description": "设置月度预算后，可在首页看到预算进度和提醒。",
        }]
    progress = budget_progress or 0
    if progress >= 0.8:
        return [{
            "id": "budget_progress_warning",
            "type": "budget",
            "level": "critical" if progress >= 1 else "warning",
            "title": "预算已超出" if progress >= 1 else "预算接近上限",
            "description": f"本月支出已达到预算的 {progress * 100:.0f}% 。",
        }]
    return []


async def build_home_overview(db: AsyncSession, user_id: str = DEFAULT_LOCAL_USER_ID) -> dict[str, object]:
    now = datetime.now(timezone.utc)
    month_start, month_end = _month_range()
    period_key = now.strftime("%Y-%m")
    memos = await _active_memos(db, user_id)
    memo_total = await _active_memo_count(db, user_id)
    tasks = await _active_tasks(db, user_id)
    strategies = await _task_strategy_map(db, user_id)
    transactions = await _active_transactions(db, user_id)
    month_transactions = [
        tx for tx in transactions if month_start <= (_to_utc(tx.occurred_at) or now) < month_end
    ]
    task_todo = [task for task in tasks if task.task_status == "todo"]
    task_overdue = [
        task for task in task_todo if _to_utc(task.due_at) is not None and _to_utc(task.due_at) < now
    ]
    task_due_today = [task for task in task_todo if _same_utc_day(task.due_at, now)]

    month_expense = sum(float(tx.amount) for tx in month_transactions if tx.direction == "expense")
    month_income = sum(float(tx.amount) for tx in month_transactions if tx.direction == "income")
    budget = await _monthly_budget(db, user_id, period_key)
    budget_amount = float(budget.amount) if budget else None
    budget_used = round(month_expense, 2) if budget else None
    budget_progress = month_expense / budget_amount if budget_amount and budget_amount > 0 else None
    budget_remaining = None if budget_amount is None else round(budget_amount - month_expense, 2)
    budget_state = "configured" if budget else "not_configured"
    category_breakdown = await _category_breakdown(db, user_id, month_start, month_end)
    finance_insights = _finance_insights(
        budget_state=budget_state,
        budget_progress=budget_progress,
    )
    sync_summary = await _sync_summary(db, user_id)
    import_summary = await _import_summary(db, user_id)

    return {
        "schema_version": HOME_OVERVIEW_SCHEMA_VERSION,
        "generated_at": now.isoformat(),
        "user_timezone": "UTC",
        "source_mode": "api",
        "attention_items": _build_attention_items(tasks, strategies, now),
        "today_metrics": {
            "memo_total": memo_total,
            "task_todo": len(task_todo),
            "task_total": len(tasks),
            "task_overdue": len(task_overdue),
            "task_due_today": len(task_due_today),
        },
        "finance_overview": {
            "month_income": round(month_income, 2),
            "month_expense": round(month_expense, 2),
            "transaction_count": len(month_transactions),
            "budget_state": budget_state,
            "budget_amount": budget_amount,
            "budget_used": budget_used,
            "budget_progress": budget_progress,
            "budget_remaining": budget_remaining,
            "currency": budget.currency if budget else "CNY",
            "category_breakdown": category_breakdown,
            "insights": finance_insights,
        },
        "finance_insights": finance_insights,
        "daily_trend": _build_daily_trend(transactions, now),
        "recent_activity": _build_recent_activity(memos, tasks, transactions),
        "sync_summary": sync_summary,
        "import_summary": import_summary,
        "settings_summary": _settings_summary(),
    }


# ─── 跨模块搜索 ──────────────────────────────────────────────────────────────

@router.get("/search", response_model=ApiResponse)
async def search_all(
    q: str = Query(min_length=1),
    entity_type: str | None = Query(default=None),
    limit: int = Query(default=10, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    results: list[dict] = []

    # 搜索备忘
    if not entity_type or entity_type == "memo":
        memo_query = select(Memo).where(
            Memo.user_id == DEFAULT_LOCAL_USER_ID,
            Memo.status == "active",
            Memo.title.ilike(f"%{q}%") | Memo.content_markdown.ilike(f"%{q}%"),
        ).order_by(Memo.created_at.desc()).limit(limit)
        memo_result = await db.execute(memo_query)
        for m in memo_result.scalars().all():
            results.append({
                "entity_type": "memo",
                "entity_id": m.id,
                "title": m.title or "无标题",
                "snippet": (m.content_markdown or "")[:100],
                "created_at": m.created_at.isoformat() if m.created_at else None,
            })

    # 搜索账单
    if not entity_type or entity_type == "ledger":
        tx_query = select(LedgerTransaction).where(
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
            LedgerTransaction.status == "active",
            LedgerTransaction.merchant.ilike(f"%{q}%") | LedgerTransaction.note.ilike(f"%{q}%"),
        ).order_by(LedgerTransaction.occurred_at.desc()).limit(limit)
        tx_result = await db.execute(tx_query)
        for tx in tx_result.scalars().all():
            results.append({
                "entity_type": "ledger",
                "entity_id": tx.id,
                "title": f"{tx.merchant or '未知'} - {tx.amount:.2f} {tx.currency}",
                "snippet": tx.note or "",
                "created_at": tx.occurred_at.isoformat() if tx.occurred_at else None,
            })

    # 搜索任务
    if not entity_type or entity_type == "task":
        task_query = select(Task).where(
            Task.user_id == DEFAULT_LOCAL_USER_ID,
            Task.status == "active",
            Task.title.ilike(f"%{q}%") | Task.description.ilike(f"%{q}%"),
        ).order_by(Task.created_at.desc()).limit(limit)
        task_result = await db.execute(task_query)
        for t in task_result.scalars().all():
            results.append({
                "entity_type": "task",
                "entity_id": t.id,
                "title": t.title,
                "snippet": (t.description or "")[:100],
                "created_at": t.created_at.isoformat() if t.created_at else None,
            })

    results.sort(key=lambda r: r.get("created_at") or "", reverse=True)
    return ApiResponse(data={"q": q, "total": len(results), "items": results[:limit]})


# ─── 标签统计与元数据 ───────────────────────────────────────────────────────────

def _tag_metadata_data(item: TagMetadata) -> dict[str, object | None]:
    return {
        "id": item.id,
        "name": item.name,
        "kind": item.kind,
        "color_token": item.color_token,
        "icon_token": item.icon_token,
        "sort_order": item.sort_order,
        "status": item.status,
        "created_at": item.created_at.isoformat() if item.created_at else None,
        "updated_at": item.updated_at.isoformat() if item.updated_at else None,
    }


@router.get("/tags/metadata", response_model=ApiResponse)
async def list_tag_metadata(
    kind: str = Query(default="memo"),
    status: str = Query(default="active"),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TagMetadata)
        .where(
            TagMetadata.user_id == DEFAULT_LOCAL_USER_ID,
            TagMetadata.kind == kind,
            TagMetadata.status == status,
        )
        .order_by(TagMetadata.sort_order.asc(), TagMetadata.name.asc())
    )
    return ApiResponse(data=[_tag_metadata_data(item) for item in result.scalars().all()])


@router.post("/tags/metadata", response_model=ApiResponse)
async def upsert_tag_metadata(
    data: TagMetadataUpsert = Body(),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TagMetadata).where(
            TagMetadata.user_id == DEFAULT_LOCAL_USER_ID,
            TagMetadata.name == data.name.strip(),
            TagMetadata.kind == data.kind,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        item = TagMetadata(
            user_id=DEFAULT_LOCAL_USER_ID,
            name=data.name.strip(),
            kind=data.kind,
        )
        db.add(item)
    item.color_token = data.color_token
    item.icon_token = data.icon_token
    item.sort_order = data.sort_order
    item.status = data.status
    await db.commit()
    await db.refresh(item)
    return ApiResponse(data=_tag_metadata_data(item))


@router.delete("/tags/metadata/{tag_name}", response_model=ApiResponse)
async def delete_tag_metadata(
    tag_name: str,
    kind: str = Query(default="memo"),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(TagMetadata).where(
            TagMetadata.user_id == DEFAULT_LOCAL_USER_ID,
            TagMetadata.name == tag_name,
            TagMetadata.kind == kind,
        )
    )
    item = result.scalar_one_or_none()
    if item is None:
        raise HTTPException(status_code=404, detail="Tag metadata not found")
    item.status = "deleted"
    await db.commit()
    await db.refresh(item)
    return ApiResponse(data=_tag_metadata_data(item))


@router.get("/tags/summary", response_model=ApiResponse)
async def tag_summary(
    kind: str = Query(default="memo"),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(
            MemoClassification.tag.label("tag"),
            func.count().label("count"),
            func.sum(case((MemoClassification.status == "confirmed", 1), else_=0)).label("confirmed_count"),
            func.sum(case((MemoClassification.status == "suggested", 1), else_=0)).label("suggested_count"),
            TagMetadata.color_token.label("color_token"),
            TagMetadata.icon_token.label("icon_token"),
            TagMetadata.sort_order.label("sort_order"),
        )
        .select_from(MemoClassification)
        .join(
            TagMetadata,
            (TagMetadata.name == MemoClassification.tag)
            & (TagMetadata.kind == kind)
            & (TagMetadata.status == "active"),
            isouter=True,
        )
        .where(
            MemoClassification.user_id == DEFAULT_LOCAL_USER_ID,
            MemoClassification.status != "rejected",
        )
        .group_by(
            MemoClassification.tag,
            TagMetadata.color_token,
            TagMetadata.icon_token,
            TagMetadata.sort_order,
        )
        .order_by(func.count().desc(), MemoClassification.tag.asc())
    )
    rows = result.all()
    return ApiResponse(data=[{
        "tag": row.tag,
        "kind": kind,
        "count": int(row.count or 0),
        "confirmed_count": int(row.confirmed_count or 0),
        "suggested_count": int(row.suggested_count or 0),
        "color_token": row.color_token,
        "icon_token": row.icon_token,
        "sort_order": row.sort_order,
    } for row in rows])


# ─── 首页统计 ─────────────────────────────────────────────────────────────────

@router.get("/home/overview", response_model=ApiResponse)
async def home_overview(db: AsyncSession = Depends(get_db)):
    return ApiResponse(data=await build_home_overview(db))


@router.get("/dashboard", response_model=ApiResponse)
async def dashboard(db: AsyncSession = Depends(get_db)):
    overview = await build_home_overview(db)
    today_metrics = overview["today_metrics"]
    finance_overview = overview["finance_overview"]
    daily_trend = overview["daily_trend"]
    recent_activity = overview["recent_activity"]
    recent_transactions = [
        {
            "id": item["entity_id"],
            "merchant": item["title"],
            "amount": item["amount"],
            "direction": item["direction"],
            "occurred_at": item["occurred_at"],
        }
        for item in recent_activity
        if item.get("entity_type") == "ledger_transaction"
    ][:5]

    return ApiResponse(data={
        "memo_total": today_metrics["memo_total"],
        "task_todo": today_metrics["task_todo"],
        "task_total": today_metrics["task_total"],
        "month_expense": finance_overview["month_expense"],
        "month_income": finance_overview["month_income"],
        "daily_trend": daily_trend,
        "recent_transactions": recent_transactions,
    })
