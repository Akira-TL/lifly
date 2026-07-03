from __future__ import annotations

import csv
import hashlib
import io
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select

from app.db.models import Asset, LedgerTransaction, Memo, Task

EXPORT_CONTRACT_VERSION = "export.v0.5.6"
EXPORT_ENCODING = "utf-8"
EXPORT_BOM_ENCODING = "utf-8-sig"
SUPPORTED_EXPORT_ENTITY_TYPES = ("ledger_transactions", "memos", "tasks", "assets", "all")


@dataclass(frozen=True)
class ExportResult:
    entity_type: str
    format: str
    media_type: str
    filename: str
    content: bytes
    counts: dict[str, int]
    checksum_sha256: str
    contract_version: str = EXPORT_CONTRACT_VERSION

    @property
    def size_bytes(self) -> int:
        return len(self.content)

    def preview_text(self, *, limit: int = 500) -> str:
        return self.content.decode(EXPORT_BOM_ENCODING, errors="replace")[:limit]

    def metadata(self) -> dict[str, Any]:
        return {
            "contract_version": self.contract_version,
            "entity_type": self.entity_type,
            "format": self.format,
            "media_type": self.media_type,
            "filename": self.filename,
            "size_bytes": self.size_bytes,
            "checksum_sha256": self.checksum_sha256,
            "counts": self.counts,
        }


async def export_entities(db, entity_type: str, user_id: str = "local-dev") -> bytes:
    """兼容旧调用方：导出实体内容 bytes。"""
    return (await build_export_result(db, entity_type, user_id=user_id)).content


async def build_export_result(db, entity_type: str, user_id: str = "local-dev") -> ExportResult:
    if entity_type not in SUPPORTED_EXPORT_ENTITY_TYPES:
        raise ValueError(f"Unknown entity type: {entity_type}")

    if entity_type == "ledger_transactions":
        content, counts = await _export_ledger_csv(db, user_id)
        return _result(entity_type, "csv", "text/csv", content, counts)
    if entity_type == "memos":
        content, counts = await _export_memos_md(db, user_id)
        return _result(entity_type, "md", "text/markdown", content, counts)
    if entity_type == "tasks":
        content, counts = await _export_tasks_json(db, user_id)
        return _result(entity_type, "json", "application/json", content, counts)
    if entity_type == "assets":
        content, counts = await _export_assets_json(db, user_id)
        return _result(entity_type, "json", "application/json", content, counts)
    if entity_type == "all":
        content, counts = await _export_all_json(db, user_id)
        return _result(entity_type, "json", "application/json", content, counts)

    raise ValueError(f"Unknown entity type: {entity_type}")


def _result(
    entity_type: str,
    format: str,
    media_type: str,
    content: bytes,
    counts: dict[str, int],
) -> ExportResult:
    checksum = hashlib.sha256(content).hexdigest()
    filename = f"lifly-export-{entity_type}.{format}"
    return ExportResult(
        entity_type=entity_type,
        format=format,
        media_type=media_type,
        filename=filename,
        content=content,
        counts=counts,
        checksum_sha256=checksum,
    )


async def _export_ledger_csv(db, user_id: str) -> tuple[bytes, dict[str, int]]:
    result = await db.execute(
        select(LedgerTransaction)
        .where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
        )
        .order_by(LedgerTransaction.occurred_at.desc())
    )
    txs = result.scalars().all()

    output = io.StringIO()
    fieldnames = [
        "id",
        "occurred_at",
        "direction",
        "amount",
        "currency",
        "merchant",
        "note",
        "source",
        "import_batch_id",
        "created_at",
        "updated_at",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()
    for tx in txs:
        writer.writerow(_ledger_export_dict(tx))
    return output.getvalue().encode(EXPORT_BOM_ENCODING), {"ledger_transactions": len(txs)}


async def _export_memos_md(db, user_id: str) -> tuple[bytes, dict[str, int]]:
    result = await db.execute(
        select(Memo)
        .where(
            Memo.user_id == user_id,
            Memo.status == "active",
        )
        .order_by(Memo.created_at.desc())
    )
    memos = result.scalars().all()

    lines = [
        "# Lifly 备忘导出",
        "",
        f"- contract_version: {EXPORT_CONTRACT_VERSION}",
        f"- exported_at: {_now_iso()}",
        f"- total: {len(memos)}",
        "",
        "---",
        "",
    ]
    for memo in memos:
        lines.extend([
            f"## {memo.title or '无标题'}",
            "",
            f"- id: {memo.id}",
            f"- type: {memo.type}",
            f"- mood: {memo.mood or ''}",
            f"- tags: {', '.join(memo.tags or [])}",
            f"- created_at: {_iso(memo.created_at)}",
            f"- updated_at: {_iso(memo.updated_at)}",
            "",
            memo.content_markdown or "",
            "",
            "---",
            "",
        ])
    return "\n".join(lines).encode(EXPORT_ENCODING), {"memos": len(memos)}


async def _export_tasks_json(db, user_id: str) -> tuple[bytes, dict[str, int]]:
    result = await db.execute(
        select(Task)
        .where(
            Task.user_id == user_id,
            Task.status == "active",
        )
        .order_by(Task.created_at.desc())
    )
    tasks = result.scalars().all()
    payload = {
        "contract_version": EXPORT_CONTRACT_VERSION,
        "exported_at": _now_iso(),
        "counts": {"tasks": len(tasks)},
        "tasks": [_task_export_dict(task) for task in tasks],
    }
    return _json_bytes(payload), {"tasks": len(tasks)}


async def _export_assets_json(db, user_id: str) -> tuple[bytes, dict[str, int]]:
    result = await db.execute(
        select(Asset)
        .where(
            Asset.user_id == user_id,
            Asset.status == "active",
        )
        .order_by(Asset.created_at.desc())
    )
    assets = result.scalars().all()
    payload = {
        "contract_version": EXPORT_CONTRACT_VERSION,
        "exported_at": _now_iso(),
        "counts": {"assets": len(assets)},
        "assets": [_asset_export_dict(asset) for asset in assets],
    }
    return _json_bytes(payload), {"assets": len(assets)}


async def _export_all_json(db, user_id: str) -> tuple[bytes, dict[str, int]]:
    memo_result = await db.execute(
        select(Memo).where(Memo.user_id == user_id, Memo.status == "active")
    )
    memos = memo_result.scalars().all()

    tx_result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
        )
    )
    txs = tx_result.scalars().all()

    task_result = await db.execute(
        select(Task).where(Task.user_id == user_id, Task.status == "active")
    )
    tasks = task_result.scalars().all()

    asset_result = await db.execute(
        select(Asset).where(Asset.user_id == user_id, Asset.status == "active")
    )
    assets = asset_result.scalars().all()

    counts = {
        "memos": len(memos),
        "ledger_transactions": len(txs),
        "tasks": len(tasks),
        "assets": len(assets),
    }
    payload = {
        "contract_version": EXPORT_CONTRACT_VERSION,
        "exported_at": _now_iso(),
        "counts": counts,
        "memos": [_memo_export_dict(memo) for memo in memos],
        "ledger_transactions": [_ledger_export_dict(tx) for tx in txs],
        "tasks": [_task_export_dict(task) for task in tasks],
        "assets": [_asset_export_dict(asset) for asset in assets],
    }
    return _json_bytes(payload), counts


def _memo_export_dict(memo: Memo) -> dict[str, Any]:
    return _strip_sensitive({
        "id": memo.id,
        "type": memo.type,
        "title": memo.title,
        "content_markdown": memo.content_markdown,
        "tags": memo.tags,
        "mood": memo.mood,
        "status": memo.status,
        "created_at": _iso(memo.created_at),
        "updated_at": _iso(memo.updated_at),
    })


def _ledger_export_dict(tx: LedgerTransaction) -> dict[str, Any]:
    return _strip_sensitive({
        "id": tx.id,
        "direction": tx.direction,
        "amount": float(tx.amount),
        "currency": tx.currency,
        "account_id": tx.account_id,
        "category_id": tx.category_id,
        "merchant": tx.merchant,
        "note": tx.note,
        "occurred_at": _iso(tx.occurred_at),
        "source": tx.source,
        "import_batch_id": tx.import_batch_id,
        "status": tx.status,
        "created_at": _iso(tx.created_at),
        "updated_at": _iso(tx.updated_at),
    })


def _task_export_dict(task: Task) -> dict[str, Any]:
    return _strip_sensitive({
        "id": task.id,
        "title": task.title,
        "description": task.description,
        "task_status": task.task_status,
        "priority": task.priority,
        "due_at": _iso(task.due_at),
        "remind_at": _iso(task.remind_at),
        "completed_at": _iso(task.completed_at),
        "source": task.source,
        "status": task.status,
        "created_at": _iso(task.created_at),
        "updated_at": _iso(task.updated_at),
    })


def _asset_export_dict(asset: Asset) -> dict[str, Any]:
    return _strip_sensitive({
        "id": asset.id,
        "kind": asset.kind,
        "asset_type": asset.asset_type,
        "filename": asset.filename,
        "mime_type": asset.mime_type,
        "size_bytes": asset.size_bytes,
        "external_url": asset.external_url,
        "external_provider": asset.external_provider,
        "visibility": asset.visibility,
        "sync_status": asset.sync_status,
        "status": asset.status,
        "created_at": _iso(asset.created_at),
        "updated_at": _iso(asset.updated_at),
    })


def _strip_sensitive(data: dict[str, Any]) -> dict[str, Any]:
    sensitive_keys = {
        "user_id",
        "storage_key",
        "sha256",
        "source_capture_id",
        "deleted_at",
        "hashed_password",
        "token_hash",
    }
    return {key: value for key, value in data.items() if key not in sensitive_keys}


def _json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False, indent=2).encode(EXPORT_ENCODING)


def _iso(value: Any) -> str | None:
    return value.isoformat() if value else None


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
