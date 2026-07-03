from __future__ import annotations

import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from fastapi.responses import StreamingResponse
import io

from app.core.database import get_db
from app.db.models import (
    ImportBatch,
    ImportRow,
    LedgerTransaction,
    AuditLog,
)
from app.schemas.common import ApiResponse, json_serialize
from app.modules.imexport.csv_parser import (
    PARSERS,
    ParsedRow,
    ParseResult,
    compute_file_hash,
)
from app.modules.imexport.exporter import export_entities

router = APIRouter()


async def _write_audit(
    db: AsyncSession,
    user_id: str,
    action: str,
    entity_type: str,
    entity_id: str,
    before: dict | None = None,
    after: dict | None = None,
    source: str = "import",
):
    log = AuditLog(
        user_id=user_id,
        actor_type="user",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=before,
        after_snapshot=after,
        source_channel=source,
    )
    db.add(log)


# ─── Import: Upload & Preview ─────────────────────────────────────────────────

@router.post("/import/upload", response_model=ApiResponse)
async def import_upload(
    file: UploadFile,
    provider: str = Query(default="auto", pattern=r"^(auto|generic|alipay|wechat)$"),
    db: AsyncSession = Depends(get_db),
):
    content = await file.read()

    parser = PARSERS.get(provider)
    if not parser:
        raise HTTPException(status_code=400, detail=f"Unknown provider: {provider}")

    parse_result = parser(content, "local-dev")
    detected_provider = parse_result.provider or provider
    file_hash = compute_file_hash(content)

    # 去重检测：相同文件 hash 是否已存在
    existing = await db.scalar(
        select(func.count()).select_from(
            select(ImportBatch).where(
                ImportBatch.user_id == "local-dev",
                ImportBatch.file_hash == file_hash,
                ImportBatch.status.in_(["committed"]),
            ).subquery()
        )
    )
    if existing and existing > 0:
        raise HTTPException(status_code=409, detail="该文件已导入过（相同文件哈希），请勿重复导入")

    batch = ImportBatch(
        user_id="local-dev",
        source_provider=detected_provider,
        filename=file.filename,
        file_hash=file_hash,
        status="preview",
        total_rows=parse_result.total_rows,
        valid_rows=parse_result.valid_rows,
        duplicate_rows=parse_result.duplicate_rows,
    )
    db.add(batch)
    await db.flush()

    for pr in parse_result.rows:
        row = ImportRow(
            batch_id=batch.id,
            row_index=pr.row_index,
            raw_data=pr.raw_data,
            parsed_data=pr.parsed if pr.status in {"valid", "ignored"} else None,
            status=pr.status if pr.status != "valid" else "pending",
            error_message=pr.error,
        )
        db.add(row)

    await db.commit()
    await db.refresh(batch)

    return ApiResponse(data={
        "batch_id": batch.id,
        "source_provider": detected_provider,
        "total_rows": batch.total_rows,
        "valid_rows": batch.valid_rows,
        "duplicate_rows": batch.duplicate_rows,
        "error_rows": parse_result.error_rows,
        "ignored_rows": parse_result.ignored_rows,
        "preview": [
            {
                "row_index": pr.row_index,
                "raw_data": pr.raw_data,
                "parsed": pr.parsed,
                "status": pr.status,
                "error": pr.error,
            }
            for pr in parse_result.rows[:20]  # 只返回前 20 行预览
        ],
    })


# ─── Import: Preview detail (all rows) ────────────────────────────────────────

@router.get("/import/{batch_id}/preview", response_model=ApiResponse)
async def import_preview(
    batch_id: str,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    batch = await db.scalar(
        select(ImportBatch).where(
            ImportBatch.id == batch_id,
            ImportBatch.user_id == "local-dev",
        ).limit(1)
    )
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")

    result = await db.execute(
        select(ImportRow).where(ImportRow.batch_id == batch_id)
        .order_by(ImportRow.row_index)
        .limit(limit).offset(offset)
    )
    rows = result.scalars().all()

    return ApiResponse(data={
        "batch": {
            "id": batch.id,
            "status": batch.status,
            "filename": batch.filename,
            "total_rows": batch.total_rows,
            "valid_rows": batch.valid_rows,
            "duplicate_rows": batch.duplicate_rows,
        },
        "total": batch.total_rows,
        "limit": limit,
        "offset": offset,
        "items": [
            {
                "id": r.id,
                "row_index": r.row_index,
                "raw_data": r.raw_data,
                "parsed_data": r.parsed_data,
                "status": r.status,
                "error_message": r.error_message,
            }
            for r in rows
        ],
    })


# ─── Import: Commit ───────────────────────────────────────────────────────────

@router.post("/import/{batch_id}/commit", response_model=ApiResponse)
async def import_commit(batch_id: str, db: AsyncSession = Depends(get_db)):
    batch = await db.scalar(
        select(ImportBatch).where(
            ImportBatch.id == batch_id,
            ImportBatch.user_id == "local-dev",
        ).limit(1)
    )
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")
    if batch.status != "preview":
        raise HTTPException(status_code=400, detail=f"Batch status is {batch.status}, expected preview")

    result = await db.execute(
        select(ImportRow).where(
            ImportRow.batch_id == batch_id,
            ImportRow.status.in_(["pending", "valid"]),
        ).order_by(ImportRow.row_index)
    )
    rows = result.scalars().all()

    imported = 0
    for row in rows:
        if not row.parsed_data:
            row.status = "error"
            row.error_message = "No parsed data"
            continue

        occurred_at = None
        if row.parsed_data.get("occurred_at"):
            try:
                occurred_at = datetime.fromisoformat(row.parsed_data["occurred_at"])
            except (ValueError, TypeError):
                occurred_at = datetime.now(timezone.utc)

        # 去重：同商户+同金额+同时间（避免重复导入；同一天也可多次消费）
        dup = await db.scalar(
            select(LedgerTransaction).where(
                LedgerTransaction.user_id == "local-dev",
                LedgerTransaction.merchant == row.parsed_data.get("merchant", ""),
                LedgerTransaction.amount == row.parsed_data.get("amount", 0),
                LedgerTransaction.occurred_at == occurred_at,
                LedgerTransaction.status == "active",
            ).limit(1)
        )
        if dup:
            row.status = "duplicate"
            batch.duplicate_rows = (batch.duplicate_rows or 0) + 1
            continue

        tx = LedgerTransaction(
            user_id="local-dev",
            direction=row.parsed_data.get("direction", "expense"),
            amount=row.parsed_data.get("amount", 0),
            currency=row.parsed_data.get("currency", "CNY"),
            merchant=row.parsed_data.get("merchant"),
            note=row.parsed_data.get("note") or row.parsed_data.get("category_hint"),
            occurred_at=occurred_at or datetime.now(timezone.utc),
            source="import",
            import_batch_id=batch_id,
        )
        db.add(tx)
        await db.flush()

        row.status = "imported"
        row.transaction_id = tx.id
        imported += 1

    batch.status = "committed"
    batch.committed_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(batch)
    return ApiResponse(data={"batch_id": batch_id, "imported": imported, "status": "committed"})


# ─── Import: Rollback ─────────────────────────────────────────────────────────

@router.post("/import/{batch_id}/rollback", response_model=ApiResponse)
async def import_rollback(batch_id: str, db: AsyncSession = Depends(get_db)):
    batch = await db.scalar(
        select(ImportBatch).where(
            ImportBatch.id == batch_id,
            ImportBatch.user_id == "local-dev",
        ).limit(1)
    )
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")
    if batch.status != "committed":
        raise HTTPException(status_code=400, detail=f"Batch status is {batch.status}, expected committed")

    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.import_batch_id == batch_id,
            LedgerTransaction.user_id == "local-dev",
        )
    )
    txs = result.scalars().all()

    now = datetime.now(timezone.utc)
    rolled = 0
    for tx in txs:
        tx.status = "user_trashed"
        tx.deleted_at = now
        tx.revision += 1
        rolled += 1

    batch.status = "rolled_back"
    batch.rolled_back_at = now

    await _write_audit(db, "local-dev", "rollback", "import_batch", batch_id)

    await db.commit()
    return ApiResponse(data={"batch_id": batch_id, "rolled_back": rolled, "status": "rolled_back"})


# ─── Import: List batches ─────────────────────────────────────────────────────

@router.get("/import/batches", response_model=ApiResponse)
async def list_batches(
    status: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    query = select(ImportBatch).where(ImportBatch.user_id == "local-dev")
    if status:
        query = query.where(ImportBatch.status == status)
    query = query.order_by(ImportBatch.created_at.desc()).limit(limit).offset(offset)

    total = await db.scalar(select(func.count()).select_from(query.subquery()))
    result = await db.execute(query)
    batches = result.scalars().all()

    return ApiResponse(data={
        "total": total or 0,
        "limit": limit,
        "offset": offset,
        "items": [
            {
                "id": b.id,
                "filename": b.filename,
                "status": b.status,
                "total_rows": b.total_rows,
                "valid_rows": b.valid_rows,
                "duplicate_rows": b.duplicate_rows,
                "created_at": b.created_at.isoformat() if b.created_at else None,
                "committed_at": b.committed_at.isoformat() if b.committed_at else None,
                "rolled_back_at": b.rolled_back_at.isoformat() if b.rolled_back_at else None,
            }
            for b in batches
        ],
    })


# ─── Import: Get batch detail ─────────────────────────────────────────────────

@router.get("/import/{batch_id}", response_model=ApiResponse)
async def get_batch(batch_id: str, db: AsyncSession = Depends(get_db)):
    batch = await db.scalar(
        select(ImportBatch).where(
            ImportBatch.id == batch_id,
            ImportBatch.user_id == "local-dev",
        ).limit(1)
    )
    if not batch:
        raise HTTPException(status_code=404, detail="Batch not found")

    return ApiResponse(data={
        "id": batch.id,
        "filename": batch.filename,
        "source_provider": batch.source_provider,
        "status": batch.status,
        "total_rows": batch.total_rows,
        "valid_rows": batch.valid_rows,
        "duplicate_rows": batch.duplicate_rows,
        "file_hash": batch.file_hash,
        "created_at": batch.created_at.isoformat() if batch.created_at else None,
        "committed_at": batch.committed_at.isoformat() if batch.committed_at else None,
        "rolled_back_at": batch.rolled_back_at.isoformat() if batch.rolled_back_at else None,
    })


# ─── Export ────────────────────────────────────────────────────────────────────

@router.post("/export", response_model=ApiResponse)
async def export_data(request: Request, db: AsyncSession = Depends(get_db)):
    body = await request.json()
    entity_type = body.get("entity_type", "all")
    format = body.get("format", "csv")

    content = await export_entities(db, entity_type)

    return ApiResponse(data={
        "entity_type": entity_type,
        "format": "csv" if entity_type == "ledger_transactions" else "json",
        "size_bytes": len(content),
        "preview": content.decode("utf-8", errors="replace")[:500],
    })


@router.get("/export/stream")
async def export_stream(
    entity_type: str = Query(default="all"),
    db: AsyncSession = Depends(get_db),
):
    content = await export_entities(db, entity_type)

    media_type_map = {
        "ledger_transactions": "text/csv",
        "memos": "text/markdown",
        "tasks": "application/json",
        "all": "application/json",
    }

    ext_map = {
        "ledger_transactions": "csv",
        "memos": "md",
        "tasks": "json",
        "all": "json",
    }

    return StreamingResponse(
        io.BytesIO(content),
        media_type=media_type_map.get(entity_type, "application/octet-stream"),
        headers={
            "Content-Disposition": f'attachment; filename="lifly-export-{entity_type}.{ext_map.get(entity_type, "data")}"',
        },
    )
