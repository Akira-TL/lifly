from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


# ─── Common ─────────────────────────────────────────────────────────────────
def json_serialize(obj: dict | list) -> dict | list:
    """Convert datetimes to ISO strings for JSON serialization."""
    import json
    return json.loads(json.dumps(obj, default=str))


class PaginationParams(BaseModel):
    limit: int = Field(default=20, ge=1, le=100)
    offset: int = Field(default=0, ge=0)


class PaginatedResponse(BaseModel):
    total: int
    limit: int
    offset: int
    items: list


class ApiResponse(BaseModel):
    success: bool = True
    data: dict | list | None = None
    error: str | None = None


# ─── MCP ────────────────────────────────────────────────────────────────────

class CaptureUndoRequest(BaseModel):
    undo_token: str = Field(min_length=1)


# ─── Memo ───────────────────────────────────────────────────────────────────

class MemoCreate(BaseModel):
    type: str = Field(default="memo", pattern=r"^(memo|journal|clip|doc)$")
    title: str | None = None
    content_markdown: str = ""
    tags: list[str] | None = None
    mood: str | None = None
    source_capture_id: str | None = None
    source: str | None = None


class MemoUpdate(BaseModel):
    type: str | None = Field(default=None, pattern=r"^(memo|journal|clip|doc)$")
    title: str | None = None
    content_markdown: str | None = None
    tags: list[str] | None = None
    mood: str | None = None


class MemoResponse(BaseModel):
    id: str
    user_id: str
    type: str
    title: str | None
    content_markdown: str
    tags: list | None
    mood: str | None
    status: str
    created_at: datetime
    updated_at: datetime


# ─── Ledger ─────────────────────────────────────────────────────────────────

class LedgerTransactionCreate(BaseModel):
    direction: str = Field(pattern=r"^(expense|income|transfer)$")
    amount: float = Field(gt=0)
    currency: str = "CNY"
    account_id: str | None = None
    category_id: str | None = None
    category_hint: str | None = None
    merchant: str | None = None
    note: str | None = None
    occurred_at: datetime | None = None
    source: str = "manual"
    source_capture_id: str | None = None
    confidence: float | None = None


class LedgerTransactionUpdate(BaseModel):
    direction: str | None = Field(default=None, pattern=r"^(expense|income|transfer)$")
    amount: float | None = Field(default=None, gt=0)
    currency: str | None = None
    account_id: str | None = None
    category_id: str | None = None
    merchant: str | None = None
    note: str | None = None
    occurred_at: datetime | None = None


class LedgerTransactionResponse(BaseModel):
    id: str
    user_id: str
    direction: str
    amount: float
    currency: str
    account_id: str | None
    category_id: str | None
    merchant: str | None
    note: str | None
    occurred_at: datetime
    source: str
    confidence: float | None
    status: str
    created_at: datetime
    updated_at: datetime


# ─── Task ───────────────────────────────────────────────────────────────────

class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=512)
    description: str | None = None
    due_at: datetime | None = None
    remind_at: datetime | None = None
    priority: str = Field(default="normal", pattern=r"^(low|normal|high|urgent)$")
    source_capture_id: str | None = None
    source: str | None = None


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1)
    description: str | None = None
    due_at: datetime | None = None
    remind_at: datetime | None = None
    priority: str | None = Field(default=None, pattern=r"^(low|normal|high|urgent)$")
    task_status: str | None = Field(default=None, pattern=r"^(todo|doing|done|cancelled)$")


class TaskResponse(BaseModel):
    id: str
    user_id: str
    title: str
    description: str | None
    due_at: datetime | None
    remind_at: datetime | None
    priority: str | None
    task_status: str
    status: str
    completed_at: datetime | None
    created_at: datetime
    updated_at: datetime


# ─── Asset ───────────────────────────────────────────────────────────────────

class AssetCreateUploadUrl(BaseModel):
    filename: str
    mime_type: str | None = None
    size_bytes: int | None = None
    asset_type: str = Field(default="file", pattern=r"^(image|pdf|ppt|mindmap|file|audio|video)$")


class AssetRegisterExternalUrl(BaseModel):
    external_url: str
    external_provider: str | None = None
    asset_type: str = Field(default="link", pattern=r"^(image|pdf|ppt|mindmap|file|audio|video|link|embed)$")
    title: str | None = None
    preview_url: str | None = None


class AssetUploadCompleteRequest(BaseModel):
    sha256: str | None = None
    size_bytes: int | None = None


class AssetUpdate(BaseModel):
    filename: str | None = None
    visibility: str | None = Field(default=None, pattern=r"^(private|shared|public)$")
    title: str | None = None


class AssetResponse(BaseModel):
    id: str
    user_id: str
    kind: str
    asset_type: str
    filename: str | None
    mime_type: str | None
    size_bytes: int | None
    sha256: str | None
    storage_provider: str | None
    storage_key: str | None
    external_url: str | None
    external_provider: str | None
    visibility: str
    sync_status: str
    status: str
    created_at: datetime
    updated_at: datetime