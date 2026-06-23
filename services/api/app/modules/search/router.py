from __future__ import annotations

from datetime import datetime, timezone, timedelta

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, func, extract
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Memo, LedgerTransaction, Task
from app.schemas.common import ApiResponse

router = APIRouter()


def _week_range():
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=now.weekday())
    return start.replace(hour=0, minute=0, second=0, microsecond=0), now


def _month_range():
    now = datetime.now(timezone.utc)
    return now.replace(day=1, hour=0, minute=0, second=0, microsecond=0), now


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
            Memo.user_id == "local-dev",
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
            LedgerTransaction.user_id == "local-dev",
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
            Task.user_id == "local-dev",
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


# ─── 首页统计 ─────────────────────────────────────────────────────────────────

@router.get("/dashboard", response_model=ApiResponse)
async def dashboard(db: AsyncSession = Depends(get_db)):
    user_id = "local-dev"

    # 备忘计数
    memo_total = await db.scalar(
        select(func.count()).select_from(
            select(Memo).where(Memo.user_id == user_id, Memo.status == "active").subquery()
        )
    )

    # 任务计数
    task_todo = await db.scalar(
        select(func.count()).select_from(
            select(Task).where(Task.user_id == user_id, Task.status == "active", Task.task_status == "todo").subquery()
        )
    )
    task_total = await db.scalar(
        select(func.count()).select_from(
            select(Task).where(Task.user_id == user_id, Task.status == "active").subquery()
        )
    )

    # 本月账单汇总
    month_start, _ = _month_range()
    expense_total = await db.scalar(
        select(func.sum(LedgerTransaction.amount)).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
            LedgerTransaction.direction == "expense",
            LedgerTransaction.occurred_at >= month_start,
        )
    )
    income_total = await db.scalar(
        select(func.sum(LedgerTransaction.amount)).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
            LedgerTransaction.direction == "income",
            LedgerTransaction.occurred_at >= month_start,
        )
    )

    # 本周账单趋势（按天）
    week_start, _ = _week_range()
    daily_result = await db.execute(
        select(
            func.date(LedgerTransaction.occurred_at).label("day"),
            func.sum(LedgerTransaction.amount).label("total"),
        ).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
            LedgerTransaction.direction == "expense",
            LedgerTransaction.occurred_at >= week_start,
        ).group_by("day").order_by("day")
    )
    daily_trend = [
        {"day": str(row.day), "total": float(row.total or 0)}
        for row in daily_result.all()
    ]

    # 最近交易
    recent_result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
        ).order_by(LedgerTransaction.occurred_at.desc()).limit(5)
    )
    recent_tx = [
        {
            "id": tx.id,
            "merchant": tx.merchant,
            "amount": float(tx.amount),
            "direction": tx.direction,
            "occurred_at": tx.occurred_at.isoformat() if tx.occurred_at else None,
        }
        for tx in recent_result.scalars().all()
    ]

    return ApiResponse(data={
        "memo_total": memo_total or 0,
        "task_todo": task_todo or 0,
        "task_total": task_total or 0,
        "month_expense": float(expense_total or 0),
        "month_income": float(income_total or 0),
        "daily_trend": daily_trend,
        "recent_transactions": recent_tx,
    })
