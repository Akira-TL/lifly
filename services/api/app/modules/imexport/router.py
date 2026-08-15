from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

from fastapi import APIRouter, Depends, HTTPException, Query, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from fastapi.responses import StreamingResponse
import io

from app.core.database import get_db
from app.core.security import AuthenticatedSubject
from app.db.models import (
    ImportBatch,
    ImportRow,
    LedgerTransaction,
    AuditLog,
)
from app.schemas.common import ApiResponse, json_serialize
from app.modules.imexport.csv_parser import PARSERS, compute_file_hash
from app.modules.auth.sessions import get_active_subject
from app.modules.imexport.exporter import (
    build_encrypted_backup_result,
    plaintext_export_boundary,
)

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
    # Import/export cloud audit is operational-only. Sensitive before/after
    # snapshots belong in the client-side E2EE audit envelope.
    del before, after
    log = AuditLog(
        user_id=user_id,
        actor_type="user",
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        before_snapshot=None,
        after_snapshot=None,
        source_channel=source,
        source_text=None,
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

COMMITTABLE_IMPORT_ROW_STATUSES = ("pending", "valid")
IGNORED_IMPORT_ROW_STATUSES = ("ignored", "error", "duplicate", "imported")
IMPORT_COMMIT_AUDIT_ACTION = "import_commit"
IMPORT_ROLLBACK_AUDIT_ACTION = "import_rollback"
IMPORT_BATCH_COMMIT_AUDIT_ACTION = "commit"
IMPORT_BATCH_ROLLBACK_AUDIT_ACTION = "rollback"
IMPORT_ROW_IMPORTED_STATUS = "imported"
IMPORT_ROW_ROLLED_BACK_STATUS = "rolled_back"


def _parse_import_occurred_at(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def _parse_import_amount(value: object) -> Decimal | None:
    if value is None:
        return None
    try:
        amount = Decimal(str(value)).quantize(Decimal("0.01"))
    except (InvalidOperation, ValueError):
        return None
    if amount <= 0:
        return None
    return amount


def _build_import_note(parsed: dict) -> str | None:
    parts = [
        parsed.get("note"),
        parsed.get("category_hint"),
        parsed.get("account_hint"),
        parsed.get("source_provider"),
        parsed.get("external_id"),
    ]
    normalized = [str(part).strip() for part in parts if part]
    return " | ".join(normalized) or None


def _ledger_import_snapshot(tx: LedgerTransaction, *, row: ImportRow, parsed: dict) -> dict:
    return json_serialize({
        "id": tx.id,
        "user_id": tx.user_id,
        "direction": tx.direction,
        "amount": float(tx.amount),
        "currency": tx.currency,
        "merchant": tx.merchant,
        "note": tx.note,
        "occurred_at": tx.occurred_at.isoformat() if tx.occurred_at else None,
        "source": tx.source,
        "import_batch_id": tx.import_batch_id,
        "import_row_id": row.id,
        "row_index": row.row_index,
        "source_provider": parsed.get("source_provider"),
        "external_id": parsed.get("external_id"),
        "category_hint": parsed.get("category_hint"),
        "account_hint": parsed.get("account_hint"),
        "status": tx.status,
        "deleted_at": tx.deleted_at.isoformat() if tx.deleted_at else None,
        "revision": tx.revision,
    })


async def _has_external_import_duplicate(
    db: AsyncSession,
    *,
    user_id: str,
    source_provider: str | None,
    external_id: str | None,
) -> bool:
    if not source_provider or not external_id:
        return False
    result = await db.scalar(
        select(func.count())
        .select_from(ImportRow)
        .join(ImportBatch, ImportBatch.id == ImportRow.batch_id)
        .where(
            ImportBatch.user_id == user_id,
            ImportBatch.status == "committed",
            ImportBatch.source_provider == source_provider,
            ImportRow.transaction_id.is_not(None),
            ImportRow.parsed_data["external_id"].astext == external_id,
        )
    )
    return bool(result and result > 0)


async def _has_business_import_duplicate(
    db: AsyncSession,
    *,
    user_id: str,
    direction: str,
    amount: Decimal,
    occurred_at: datetime,
    merchant: str | None,
) -> bool:
    result = await db.scalar(
        select(func.count()).select_from(
            select(LedgerTransaction)
            .where(
                LedgerTransaction.user_id == user_id,
                LedgerTransaction.direction == direction,
                LedgerTransaction.amount == amount,
                LedgerTransaction.occurred_at == occurred_at,
                LedgerTransaction.merchant == (merchant or "未知"),
                LedgerTransaction.status == "active",
            )
            .subquery()
        )
    )
    return bool(result and result > 0)


async def _should_mark_import_duplicate(
    db: AsyncSession,
    *,
    user_id: str,
    parsed: dict,
    amount: Decimal,
    occurred_at: datetime,
) -> bool:
    if await _has_external_import_duplicate(
        db,
        user_id=user_id,
        source_provider=parsed.get("source_provider"),
        external_id=parsed.get("external_id"),
    ):
        return True
    return await _has_business_import_duplicate(
        db,
        user_id=user_id,
        direction=parsed.get("direction", "expense"),
        amount=amount,
        occurred_at=occurred_at,
        merchant=parsed.get("merchant"),
    )


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
            ImportRow.status.in_(COMMITTABLE_IMPORT_ROW_STATUSES),
        ).order_by(ImportRow.row_index)
    )
    rows = result.scalars().all()

    imported = 0
    duplicates = 0
    errors = 0
    skipped = 0
    for row in rows:
        parsed = row.parsed_data or {}
        if not parsed:
            row.status = "error"
            row.error_message = "No parsed data"
            errors += 1
            continue

        direction = parsed.get("direction") or "expense"
        if direction not in {"expense", "income"}:
            row.status = "ignored"
            row.error_message = "Ignored non-ledger direction"
            skipped += 1
            continue

        amount = _parse_import_amount(parsed.get("amount"))
        occurred_at = _parse_import_occurred_at(parsed.get("occurred_at"))
        if amount is None:
            row.status = "error"
            row.error_message = "Invalid amount"
            errors += 1
            continue
        if occurred_at is None:
            row.status = "error"
            row.error_message = "Invalid occurred_at"
            errors += 1
            continue

        if await _should_mark_import_duplicate(
            db,
            user_id="local-dev",
            parsed=parsed,
            amount=amount,
            occurred_at=occurred_at,
        ):
            row.status = "duplicate"
            row.error_message = "Duplicate transaction"
            duplicates += 1
            continue

        tx = LedgerTransaction(
            user_id="local-dev",
            direction=direction,
            amount=amount,
            currency=parsed.get("currency") or "CNY",
            merchant=parsed.get("merchant") or "未知",
            note=_build_import_note(parsed),
            occurred_at=occurred_at,
            source="import",
            import_batch_id=batch_id,
        )
        db.add(tx)
        await db.flush()

        row.status = IMPORT_ROW_IMPORTED_STATUS
        row.transaction_id = tx.id
        row.error_message = None
        imported += 1

        await _write_audit(
            db,
            "local-dev",
            IMPORT_COMMIT_AUDIT_ACTION,
            "ledger_transaction",
            tx.id,
            after=_ledger_import_snapshot(tx, row=row, parsed=parsed),
            source="import",
        )

    batch.status = "committed"
    batch.committed_at = datetime.now(timezone.utc)
    batch.duplicate_rows = duplicates

    await _write_audit(
        db,
        "local-dev",
        IMPORT_BATCH_COMMIT_AUDIT_ACTION,
        "import_batch",
        batch_id,
        after=json_serialize({
            "batch_id": batch_id,
            "source_provider": batch.source_provider,
            "status": batch.status,
            "imported": imported,
            "duplicates": duplicates,
            "errors": errors,
            "skipped": skipped,
        }),
        source="import",
    )

    await db.commit()
    await db.refresh(batch)
    return ApiResponse(data={
        "batch_id": batch_id,
        "source_provider": batch.source_provider,
        "imported": imported,
        "duplicates": duplicates,
        "errors": errors,
        "skipped": skipped,
        "status": "committed",
    })


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
    if batch.status == "rolled_back":
        raise HTTPException(status_code=400, detail="Batch has already been rolled back")
    if batch.status != "committed":
        raise HTTPException(status_code=400, detail=f"Batch status is {batch.status}, expected committed")

    rows_result = await db.execute(
        select(ImportRow).where(
            ImportRow.batch_id == batch_id,
            ImportRow.status == IMPORT_ROW_IMPORTED_STATUS,
            ImportRow.transaction_id.is_not(None),
        ).order_by(ImportRow.row_index)
    )
    rows = rows_result.scalars().all()

    before_batch = json_serialize({
        "id": batch.id,
        "source_provider": batch.source_provider,
        "status": batch.status,
        "total_rows": batch.total_rows,
        "valid_rows": batch.valid_rows,
        "duplicate_rows": batch.duplicate_rows,
        "committed_at": batch.committed_at,
        "rolled_back_at": batch.rolled_back_at,
        "imported_rows": len(rows),
    })

    now = datetime.now(timezone.utc)
    rolled = 0
    skipped = 0
    for row in rows:
        tx = await db.scalar(
            select(LedgerTransaction).where(
                LedgerTransaction.id == row.transaction_id,
                LedgerTransaction.user_id == "local-dev",
                LedgerTransaction.import_batch_id == batch_id,
            ).limit(1)
        )
        if not tx or tx.status != "active":
            row.status = "rollback_skipped"
            row.error_message = "Transaction missing or not active"
            skipped += 1
            continue

        parsed = row.parsed_data or {}
        before_tx = _ledger_import_snapshot(tx, row=row, parsed=parsed)
        tx.status = "user_trashed"
        tx.deleted_at = now
        tx.revision += 1
        row.status = IMPORT_ROW_ROLLED_BACK_STATUS
        row.error_message = None
        rolled += 1
        after_tx = _ledger_import_snapshot(tx, row=row, parsed=parsed)

        await _write_audit(
            db,
            "local-dev",
            IMPORT_ROLLBACK_AUDIT_ACTION,
            "ledger_transaction",
            tx.id,
            before=before_tx,
            after=after_tx,
            source="import",
        )

    batch.status = "rolled_back"
    batch.rolled_back_at = now
    after_batch = json_serialize({
        "id": batch.id,
        "source_provider": batch.source_provider,
        "status": batch.status,
        "rolled_back": rolled,
        "skipped": skipped,
        "rolled_back_at": batch.rolled_back_at,
    })

    await _write_audit(
        db,
        "local-dev",
        IMPORT_BATCH_ROLLBACK_AUDIT_ACTION,
        "import_batch",
        batch_id,
        before=before_batch,
        after=after_batch,
        source="import",
    )

    await db.commit()
    return ApiResponse(data={
        "batch_id": batch_id,
        "rolled_back": rolled,
        "skipped": skipped,
        "status": "rolled_back",
    })


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
async def export_data(
    body: dict,
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
):
    mode = str(body.get("mode") or "plaintext")
    entity_type = str(body.get("entity_type") or "all")
    if mode == "plaintext":
        return ApiResponse(
            data={
                **plaintext_export_boundary().metadata(),
                "entity_type": entity_type,
                "format": "local",
                "media_type": "application/octet-stream",
                "filename": "",
                "size_bytes": 0,
                "checksum_sha256": "",
                "counts": {},
                "preview": "",
            }
        )
    if mode != "encrypted_backup":
        raise HTTPException(status_code=400, detail=f"Unknown export mode: {mode}")

    try:
        result = await build_encrypted_backup_result(
            db,
            user_id=subject.account_id,
            include_asset_ciphertext=False,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return ApiResponse(data=result.metadata())


@router.get("/export/stream")
async def export_stream(
    mode: str = Query(default="encrypted_backup"),
    entity_type: str = Query(default="all"),
    db: AsyncSession = Depends(get_db),
    subject: AuthenticatedSubject = Depends(get_active_subject),
):
    del entity_type
    if mode == "plaintext":
        raise HTTPException(
            status_code=409,
            detail="Plaintext export must be generated on the trusted client device",
        )
    if mode != "encrypted_backup":
        raise HTTPException(status_code=400, detail=f"Unknown export mode: {mode}")

    try:
        result = await build_encrypted_backup_result(
            db,
            user_id=subject.account_id,
            include_asset_ciphertext=True,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return StreamingResponse(
        io.BytesIO(result.content),
        media_type=result.media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{result.filename}"',
            "X-Lifly-Export-Contract": result.contract_version,
            "X-Lifly-Export-Mode": result.mode,
            "X-Lifly-Export-Checksum-SHA256": result.checksum_sha256,
            "X-Lifly-Export-Size-Bytes": str(result.size_bytes),
        },
    )
