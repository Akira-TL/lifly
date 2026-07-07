from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import LedgerBudget, LedgerCategory, LedgerTransaction
from app.modules.ledger.service import (
    DEFAULT_LOCAL_USER_ID,
    create_ledger_transaction_record,
    ledger_transaction_to_response,
    write_ledger_audit,
)
from app.schemas.common import (
    ApiResponse,
    LedgerTransactionCreate,
    LedgerTransactionUpdate,
    PaginatedResponse,
    json_serialize,
)

router = APIRouter()

LEDGER_OVERVIEW_SCHEMA_VERSION = "ledger_overview.v1"


def _current_period_key() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m")


def _normalize_period(period: str | None) -> str:
    if not period or period == "current_month":
        return _current_period_key()
    return period


def _period_range(period: str | None) -> tuple[str, datetime, datetime]:
    period_key = _normalize_period(period)
    try:
        year, month = [int(part) for part in period_key.split("-", 1)]
        start = datetime(year, month, 1, tzinfo=timezone.utc)
    except ValueError:
        period_key = _current_period_key()
        year, month = [int(part) for part in period_key.split("-", 1)]
        start = datetime(year, month, 1, tzinfo=timezone.utc)

    if month == 12:
        end = datetime(year + 1, 1, 1, tzinfo=timezone.utc)
    else:
        end = datetime(year, month + 1, 1, tzinfo=timezone.utc)
    return period_key, start, end


def _ledger_insights_from_overview(overview: dict) -> list[dict]:
    if overview["budget_state"] == "not_configured":
        return [{
            "id": "budget_not_configured",
            "type": "budget",
            "level": "info",
            "title": "未设置预算",
            "description": "设置月度预算后，可在首页看到预算进度和提醒。",
        }]
    progress = overview.get("budget_progress") or 0
    if progress >= 0.8:
        return [{
            "id": "budget_progress_warning",
            "type": "budget",
            "level": "critical" if progress >= 1 else "warning",
            "title": "预算已超出" if progress >= 1 else "预算接近上限",
            "description": f"本月支出已达到预算的 {progress * 100:.0f}% 。",
        }]
    return []


async def build_ledger_overview(
    db: AsyncSession,
    period: str | None,
    user_id: str = DEFAULT_LOCAL_USER_ID,
) -> dict:
    period_key, start, end = _period_range(period)
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
            LedgerTransaction.occurred_at >= start,
            LedgerTransaction.occurred_at < end,
        )
    )
    txs = result.scalars().all()
    month_expense = sum(float(tx.amount) for tx in txs if tx.direction == "expense")
    month_income = sum(float(tx.amount) for tx in txs if tx.direction == "income")
    budget = await db.scalar(
        select(LedgerBudget).where(
            LedgerBudget.user_id == user_id,
            LedgerBudget.status == "active",
            LedgerBudget.period_type == "month",
            LedgerBudget.period_key == period_key,
            LedgerBudget.category_id.is_(None),
        ).order_by(LedgerBudget.updated_at.desc())
    )
    budget_amount = float(budget.amount) if budget else None
    budget_progress = month_expense / budget_amount if budget_amount and budget_amount > 0 else None
    return {
        "schema_version": LEDGER_OVERVIEW_SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "period": period_key,
        "source_mode": "api",
        "month_income": round(month_income, 2),
        "month_expense": round(month_expense, 2),
        "transaction_count": len(txs),
        "budget_state": "configured" if budget else "not_configured",
        "budget_amount": budget_amount,
        "budget_used": round(month_expense, 2) if budget else None,
        "budget_progress": budget_progress,
        "currency": budget.currency if budget else "CNY",
    }


@router.post("/transactions", response_model=ApiResponse)
async def create_transaction(data: LedgerTransactionCreate, db: AsyncSession = Depends(get_db)):
    tx = await create_ledger_transaction_record(
        db,
        data,
        user_id=DEFAULT_LOCAL_USER_ID,
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(tx)
    return ApiResponse(data=ledger_transaction_to_response(tx).model_dump())


@router.get("/transactions", response_model=ApiResponse)
async def list_transactions(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    direction: str | None = Query(default=None),
    category_id: str | None = Query(default=None),
    start_date: str | None = Query(default=None),
    end_date: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    query = select(LedgerTransaction).where(
        LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        LedgerTransaction.status == "active",
    )
    if direction:
        query = query.where(LedgerTransaction.direction == direction)
    if category_id:
        query = query.where(LedgerTransaction.category_id == category_id)
    if start_date:
        query = query.where(LedgerTransaction.occurred_at >= start_date)
    if end_date:
        query = query.where(LedgerTransaction.occurred_at <= end_date)

    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query)

    query = query.order_by(LedgerTransaction.occurred_at.desc()).limit(limit).offset(offset)
    result = await db.execute(query)
    txs = result.scalars().all()

    return ApiResponse(
        data=PaginatedResponse(
            total=total or 0,
            limit=limit,
            offset=offset,
            items=[ledger_transaction_to_response(tx).model_dump() for tx in txs],
        ).model_dump()
    )


@router.get("/transactions/{tx_id}", response_model=ApiResponse)
async def get_transaction(tx_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return ApiResponse(data=ledger_transaction_to_response(tx).model_dump())


@router.put("/transactions/{tx_id}", response_model=ApiResponse)
async def update_transaction(tx_id: str, data: LedgerTransactionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    before = ledger_transaction_to_response(tx).model_dump()
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(tx, key, value)
    tx.revision += 1

    await write_ledger_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        action="update",
        entity_id=tx_id,
        before=json_serialize(before),
        after=json_serialize(ledger_transaction_to_response(tx).model_dump()),
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    await db.refresh(tx)
    return ApiResponse(data=ledger_transaction_to_response(tx).model_dump())


@router.delete("/transactions/{tx_id}", response_model=ApiResponse)
async def delete_transaction(tx_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    before = ledger_transaction_to_response(tx).model_dump()
    tx.status = "user_trashed"
    tx.deleted_at = datetime.now(timezone.utc)
    tx.revision += 1

    await write_ledger_audit(
        db,
        user_id=DEFAULT_LOCAL_USER_ID,
        action="trash",
        entity_id=tx_id,
        before=json_serialize(before),
        actor_type="user",
        source_channel="api",
    )
    await db.commit()
    return ApiResponse(data={"id": tx_id, "status": "user_trashed"})


# ─── Summary ────────────────────────────────────────────────────────────────

@router.get("/summary", response_model=ApiResponse)
async def get_summary(
    start_date: str | None = Query(default=None),
    end_date: str | None = Query(default=None),
    db: AsyncSession = Depends(get_db),
):
    query = select(LedgerTransaction).where(
        LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
        LedgerTransaction.status == "active",
    )
    if start_date:
        query = query.where(LedgerTransaction.occurred_at >= start_date)
    if end_date:
        query = query.where(LedgerTransaction.occurred_at <= end_date)

    result = await db.execute(query)
    txs = result.scalars().all()

    total_expense = sum(float(tx.amount) for tx in txs if tx.direction == "expense")
    total_income = sum(float(tx.amount) for tx in txs if tx.direction == "income")
    count = len(txs)

    return ApiResponse(data={
        "expense_total": round(total_expense, 2),
        "income_total": round(total_income, 2),
        "transaction_count": count,
    })


@router.get("/overview", response_model=ApiResponse)
async def get_ledger_overview(
    period: str | None = Query(default="current_month"),
    db: AsyncSession = Depends(get_db),
):
    return ApiResponse(data=await build_ledger_overview(db, period))


@router.get("/categories/summary", response_model=ApiResponse)
async def get_category_summary(
    period: str | None = Query(default="current_month"),
    direction: str = Query(default="expense"),
    db: AsyncSession = Depends(get_db),
):
    period_key, start, end = _period_range(period)
    result = await db.execute(
        select(
            LedgerTransaction.category_id.label("category_id"),
            LedgerCategory.name.label("category_name"),
            func.sum(LedgerTransaction.amount).label("amount"),
            func.count().label("transaction_count"),
        )
        .select_from(LedgerTransaction)
        .join(LedgerCategory, LedgerCategory.id == LedgerTransaction.category_id, isouter=True)
        .where(
            LedgerTransaction.user_id == DEFAULT_LOCAL_USER_ID,
            LedgerTransaction.status == "active",
            LedgerTransaction.direction == direction,
            LedgerTransaction.occurred_at >= start,
            LedgerTransaction.occurred_at < end,
        )
        .group_by(LedgerTransaction.category_id, LedgerCategory.name)
        .order_by(func.sum(LedgerTransaction.amount).desc())
    )
    rows = result.all()
    total = sum(float(row.amount or 0) for row in rows)
    return ApiResponse(data=[{
        "period": period_key,
        "category_id": row.category_id or "uncategorized",
        "category_name": row.category_name or "未分类",
        "direction": direction,
        "amount": round(float(row.amount or 0), 2),
        "ratio": float(row.amount or 0) / total if total > 0 else 0,
        "transaction_count": int(row.transaction_count or 0),
    } for row in rows])


@router.get("/insights", response_model=ApiResponse)
async def get_ledger_insights(
    period: str | None = Query(default="current_month"),
    db: AsyncSession = Depends(get_db),
):
    overview = await build_ledger_overview(db, period)
    return ApiResponse(data=_ledger_insights_from_overview(overview))


# ─── Categories ─────────────────────────────────────────────────────────────

@router.get("/categories", response_model=ApiResponse)
async def list_categories(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerCategory).where(LedgerCategory.user_id == DEFAULT_LOCAL_USER_ID, LedgerCategory.status == "active")
        .order_by(LedgerCategory.sort_order)
    )
    cats = result.scalars().all()
    return ApiResponse(data=[{
        "id": c.id,
        "name": c.name,
        "type": c.type,
        "parent_id": c.parent_id,
        "icon": c.icon,
        "color": c.color,
    } for c in cats])
