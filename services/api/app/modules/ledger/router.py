from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import LedgerCategory, LedgerTransaction
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
