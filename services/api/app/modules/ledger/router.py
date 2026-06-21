from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import LedgerTransaction, LedgerCategory, LedgerAccount, AuditLog
from app.schemas.common import (
    LedgerTransactionCreate,
    LedgerTransactionUpdate,
    LedgerTransactionResponse,
    PaginatedResponse,
    ApiResponse,
    json_serialize,
)

router = APIRouter()


def _tx_to_response(tx: LedgerTransaction) -> LedgerTransactionResponse:
    return LedgerTransactionResponse(
        id=tx.id,
        user_id=tx.user_id,
        direction=tx.direction,
        amount=float(tx.amount),
        currency=tx.currency,
        account_id=tx.account_id,
        category_id=tx.category_id,
        merchant=tx.merchant,
        note=tx.note,
        occurred_at=tx.occurred_at,
        source=tx.source,
        confidence=float(tx.confidence) if tx.confidence else None,
        status=tx.status,
        created_at=tx.created_at,
        updated_at=tx.updated_at,
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


@router.post("/transactions", response_model=ApiResponse)
async def create_transaction(data: LedgerTransactionCreate, db: AsyncSession = Depends(get_db)):
    tx = LedgerTransaction(
        user_id="local-dev",
        direction=data.direction,
        amount=data.amount,
        currency=data.currency,
        account_id=data.account_id,
        category_id=data.category_id,
        merchant=data.merchant,
        note=data.note,
        occurred_at=data.occurred_at or datetime.now(timezone.utc),
        source=data.source,
        source_capture_id=data.source_capture_id,
        confidence=data.confidence,
    )
    db.add(tx)
    await db.flush()
    await _write_audit(db, "local-dev", "create", "ledger_transaction", tx.id, after=json_serialize(_tx_to_response(tx).model_dump()))
    await db.commit()
    await db.refresh(tx)
    return ApiResponse(data=_tx_to_response(tx).model_dump())


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
        LedgerTransaction.user_id == "local-dev",
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
            total=total or 0, limit=limit, offset=offset,
            items=[_tx_to_response(tx).model_dump() for tx in txs],
        ).model_dump()
    )


@router.get("/transactions/{tx_id}", response_model=ApiResponse)
async def get_transaction(tx_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == "local-dev",
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
    return ApiResponse(data=_tx_to_response(tx).model_dump())


@router.put("/transactions/{tx_id}", response_model=ApiResponse)
async def update_transaction(tx_id: str, data: LedgerTransactionUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == "local-dev",
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    before = _tx_to_response(tx).model_dump()
    update_data = data.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(tx, key, value)
    tx.revision += 1

    await _write_audit(db, "local-dev", "update", "ledger_transaction", tx_id, before=json_serialize(before), after=json_serialize(_tx_to_response(tx).model_dump()))
    await db.commit()
    await db.refresh(tx)
    return ApiResponse(data=_tx_to_response(tx).model_dump())


@router.delete("/transactions/{tx_id}", response_model=ApiResponse)
async def delete_transaction(tx_id: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.id == tx_id,
            LedgerTransaction.user_id == "local-dev",
        )
    )
    tx = result.scalar_one_or_none()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")

    before = _tx_to_response(tx).model_dump()
    tx.status = "user_trashed"
    tx.deleted_at = datetime.now(timezone.utc)
    tx.revision += 1

    await _write_audit(db, "local-dev", "trash", "ledger_transaction", tx_id, before=json_serialize(before))
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
        LedgerTransaction.user_id == "local-dev",
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
        "total_expense": round(total_expense, 2),
        "total_income": round(total_income, 2),
        "total_transactions": count,
    })


# ─── Categories ─────────────────────────────────────────────────────────────

@router.get("/categories", response_model=ApiResponse)
async def list_categories(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(LedgerCategory).where(LedgerCategory.user_id == "local-dev", LedgerCategory.status == "active")
        .order_by(LedgerCategory.sort_order)
    )
    cats = result.scalars().all()
    return ApiResponse(data=[{
        "id": c.id, "name": c.name, "type": c.type,
        "parent_id": c.parent_id, "icon": c.icon, "color": c.color,
    } for c in cats])
