from __future__ import annotations

import csv
import io
import json
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select, func

from app.db.models import (
    Memo,
    LedgerTransaction,
    Task,
    Asset,
)


async def export_entities(db, entity_type: str, user_id: str = "local-dev") -> bytes:
    """导出来自某类实体的全部数据。"""
    if entity_type == "ledger_transactions":
        return await _export_csv(db, user_id)
    elif entity_type == "memos":
        return await _export_memos_md(db, user_id)
    elif entity_type == "tasks":
        return await _export_tasks_json(db, user_id)
    elif entity_type == "all":
        return await _export_all_json(db, user_id)
    else:
        raise ValueError(f"Unknown entity type: {entity_type}")


async def _export_csv(db, user_id: str) -> bytes:
    result = await db.execute(
        select(LedgerTransaction).where(
            LedgerTransaction.user_id == user_id,
            LedgerTransaction.status == "active",
        ).order_by(LedgerTransaction.occurred_at.desc())
    )
    txs = result.scalars().all()

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=[
        "id", "occurred_at", "direction", "amount", "currency", "merchant", "note", "created_at",
    ])
    writer.writeheader()
    for tx in txs:
        writer.writerow({
            "id": tx.id,
            "occurred_at": tx.occurred_at.isoformat() if tx.occurred_at else "",
            "direction": tx.direction,
            "amount": f"{tx.amount:.2f}",
            "currency": tx.currency,
            "merchant": tx.merchant or "",
            "note": tx.note or "",
            "created_at": tx.created_at.isoformat() if tx.created_at else "",
        })
    return output.getvalue().encode("utf-8-sig")


async def _export_memos_md(db, user_id: str) -> bytes:
    result = await db.execute(
        select(Memo).where(
            Memo.user_id == user_id,
            Memo.status == "active",
        ).order_by(Memo.created_at.desc())
    )
    memos = result.scalars().all()

    lines = ["# Lifily 备忘导出\n", f"导出时间: {datetime.now(timezone.utc).isoformat()}\n\n---\n"]
    for m in memos:
        lines.append(f"## {m.title or '无标题'}\n")
        lines.append(f"类型: {m.type} | 情绪: {m.mood or '无'} | 创建: {m.created_at.isoformat() if m.created_at else ''}\n\n")
        lines.append(m.content_markdown or "")
        lines.append("\n\n---\n\n")
    return "\n".join(lines).encode("utf-8")


async def _export_tasks_json(db, user_id: str) -> bytes:
    result = await db.execute(
        select(Task).where(
            Task.user_id == user_id,
            Task.status == "active",
        ).order_by(Task.created_at.desc())
    )
    tasks = result.scalars().all()

    return json.dumps([{
        "id": t.id,
        "title": t.title,
        "description": t.description,
        "task_status": t.task_status,
        "priority": t.priority,
        "due_at": t.due_at.isoformat() if t.due_at else None,
        "remind_at": t.remind_at.isoformat() if t.remind_at else None,
        "completed_at": t.completed_at.isoformat() if t.completed_at else None,
        "created_at": t.created_at.isoformat() if t.created_at else None,
    } for t in tasks], ensure_ascii=False, indent=2).encode("utf-8")


async def _export_all_json(db, user_id: str) -> bytes:
    # 备忘
    memo_result = await db.execute(
        select(Memo).where(Memo.user_id == user_id, Memo.status == "active")
    )
    memos = memo_result.scalars().all()

    # 账单
    tx_result = await db.execute(
        select(LedgerTransaction).where(LedgerTransaction.user_id == user_id, LedgerTransaction.status == "active")
    )
    txs = tx_result.scalars().all()

    # 任务
    task_result = await db.execute(
        select(Task).where(Task.user_id == user_id, Task.status == "active")
    )
    tasks = task_result.scalars().all()

    return json.dumps({
        "version": "0.5.0",
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "memos": [{
            "id": m.id, "type": m.type, "title": m.title,
            "content_markdown": m.content_markdown, "tags": m.tags,
            "mood": m.mood, "created_at": m.created_at.isoformat() if m.created_at else None,
        } for m in memos],
        "ledger_transactions": [{
            "id": tx.id, "direction": tx.direction, "amount": float(tx.amount),
            "currency": tx.currency, "merchant": tx.merchant, "note": tx.note,
            "occurred_at": tx.occurred_at.isoformat() if tx.occurred_at else None,
            "created_at": tx.created_at.isoformat() if tx.created_at else None,
        } for tx in txs],
        "tasks": [{
            "id": t.id, "title": t.title, "description": t.description,
            "task_status": t.task_status, "priority": t.priority,
            "remind_at": t.remind_at.isoformat() if t.remind_at else None,
            "created_at": t.created_at.isoformat() if t.created_at else None,
        } for t in tasks],
    }, ensure_ascii=False, indent=2).encode("utf-8")
