from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import expression


class Base(DeclarativeBase):
    pass


def new_uuid() -> str:
    return str(uuid.uuid4())


def utcnow() -> datetime:
    return datetime.utcnow()


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class SoftDeleteMixin:
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RevisionMixin:
    revision: Mapped[int] = mapped_column(Integer, default=1, nullable=False)


# ─── Memo ───────────────────────────────────────────────────────────────────

class TagMetadata(Base, TimestampMixin):
    __tablename__ = "tag_metadata"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    kind: Mapped[str] = mapped_column(String(16), nullable=False, default="memo")
    color_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    icon_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    sort_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class Memo(Base, TimestampMixin, SoftDeleteMixin, RevisionMixin):
    __tablename__ = "memos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(16), nullable=False, default="memo")
    title: Mapped[str | None] = mapped_column(String(512), nullable=True)
    content_markdown: Mapped[str] = mapped_column(Text, nullable=False, default="")
    tags: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    mood: Mapped[str | None] = mapped_column(String(64), nullable=True)
    source_capture_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    source: Mapped[str | None] = mapped_column(String(32), nullable=True)

    assets: Mapped[list[MemoAssetRef]] = relationship(
        "MemoAssetRef", back_populates="memo", cascade="all, delete-orphan"
    )


class MemoClassification(Base, TimestampMixin):
    __tablename__ = "memo_classifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    memo_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    tag: Mapped[str] = mapped_column(String(128), nullable=False)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="ai")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="suggested")
    confidence: Mapped[float | None] = mapped_column(Numeric(5, 4), nullable=True)
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


# ─── Asset ──────────────────────────────────────────────────────────────────

class Asset(Base, TimestampMixin):
    __tablename__ = "assets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    kind: Mapped[str] = mapped_column(String(16), nullable=False)  # internal / external
    asset_type: Mapped[str] = mapped_column(String(32), nullable=False)
    filename: Mapped[str | None] = mapped_column(String(512), nullable=True)
    mime_type: Mapped[str | None] = mapped_column(String(128), nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    storage_provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    storage_key: Mapped[str | None] = mapped_column(String(512), nullable=True)
    external_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    external_provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    visibility: Mapped[str] = mapped_column(String(16), nullable=False, default="private")
    sync_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class MemoAssetRef(Base, TimestampMixin):
    __tablename__ = "memo_asset_refs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    memo_id: Mapped[str] = mapped_column(String(36), ForeignKey("memos.id"), nullable=False)
    asset_id: Mapped[str] = mapped_column(String(36), ForeignKey("assets.id"), nullable=False)
    ref_type: Mapped[str] = mapped_column(String(16), nullable=False)
    position_hint: Mapped[str | None] = mapped_column(String(64), nullable=True)

    memo: Mapped[Memo] = relationship("Memo", back_populates="assets")


# ─── Ledger ─────────────────────────────────────────────────────────────────

class LedgerAccount(Base, TimestampMixin):
    __tablename__ = "ledger_accounts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    type: Mapped[str] = mapped_column(String(16), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="CNY")
    is_default: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class LedgerCategory(Base, TimestampMixin):
    __tablename__ = "ledger_categories"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    parent_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    type: Mapped[str] = mapped_column(String(16), nullable=False)  # expense / income / transfer
    icon: Mapped[str | None] = mapped_column(String(64), nullable=True)
    color: Mapped[str | None] = mapped_column(String(16), nullable=True)
    sort_order: Mapped[int | None] = mapped_column(Integer, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class LedgerTransaction(Base, TimestampMixin, SoftDeleteMixin, RevisionMixin):
    __tablename__ = "ledger_transactions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    account_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    category_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    direction: Mapped[str] = mapped_column(String(16), nullable=False)  # expense / income / transfer
    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="CNY")
    merchant: Mapped[str | None] = mapped_column(String(256), nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="manual")
    source_capture_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    import_batch_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    confidence: Mapped[float | None] = mapped_column(Numeric(5, 4), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class LedgerBudget(Base, TimestampMixin, RevisionMixin):
    __tablename__ = "ledger_budgets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    period_type: Mapped[str] = mapped_column(String(16), nullable=False, default="month")
    period_key: Mapped[str] = mapped_column(String(16), nullable=False)
    category_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="CNY")
    alert_threshold: Mapped[float | None] = mapped_column(Numeric(5, 4), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")


class LedgerEntry(Base):
    __tablename__ = "ledger_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    transaction_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ledger_transactions.id"), nullable=False
    )
    account_id: Mapped[str] = mapped_column(String(36), nullable=False)
    entry_type: Mapped[str] = mapped_column(String(8), nullable=False)  # debit / credit
    amount: Mapped[float] = mapped_column(Numeric(18, 2), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="CNY")


# ─── Task / Reminder ────────────────────────────────────────────────────────

class Task(Base, TimestampMixin, SoftDeleteMixin, RevisionMixin):
    __tablename__ = "tasks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(512), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    due_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    remind_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    priority: Mapped[str | None] = mapped_column(String(16), nullable=True, default="normal")
    task_status: Mapped[str] = mapped_column(String(16), nullable=False, default="todo")
    source_capture_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    source: Mapped[str | None] = mapped_column(String(32), nullable=True)


class TaskReminderStrategy(Base, TimestampMixin):
    __tablename__ = "task_reminder_strategies"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    task_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    warning_level: Mapped[str] = mapped_column(String(16), nullable=False, default="normal")
    warning_reason: Mapped[str | None] = mapped_column(Text, nullable=True)
    preparation_window_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    ai_suggested_remind_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    strategy_status: Mapped[str] = mapped_column(String(20), nullable=False, default="suggested")
    source: Mapped[str] = mapped_column(String(16), nullable=False, default="ai")
    confirmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    dismissed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Reminder(Base, TimestampMixin, RevisionMixin):
    __tablename__ = "reminders"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    target_type: Mapped[str] = mapped_column(String(32), nullable=False)
    target_id: Mapped[str] = mapped_column(String(36), nullable=False)
    remind_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    channel: Mapped[str] = mapped_column(String(16), nullable=False, default="app")
    reminder_status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=3)
    next_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_attempt_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivered_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    failed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    external_id: Mapped[str | None] = mapped_column(String(256), nullable=True)
    dispatch_token: Mapped[str | None] = mapped_column(String(64), nullable=True)
    lease_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


# ─── Calendar (预留) ────────────────────────────────────────────────────────

class CalendarEvent(Base, TimestampMixin, RevisionMixin):
    __tablename__ = "calendar_events"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(512), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    location: Mapped[str | None] = mapped_column(String(512), nullable=True)
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    all_day: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    timezone: Mapped[str | None] = mapped_column(String(64), nullable=True)
    rrule: Mapped[str | None] = mapped_column(Text, nullable=True)
    external_uid: Mapped[str | None] = mapped_column(String(256), nullable=True)
    source_provider: Mapped[str | None] = mapped_column(String(32), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


# ─── Import ─────────────────────────────────────────────────────────────────

class ImportBatch(Base):
    __tablename__ = "import_batches"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    source_provider: Mapped[str] = mapped_column(String(32), nullable=False)
    filename: Mapped[str | None] = mapped_column(String(512), nullable=True)
    file_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="preview")
    total_rows: Mapped[int | None] = mapped_column(Integer, nullable=True)
    valid_rows: Mapped[int | None] = mapped_column(Integer, nullable=True)
    duplicate_rows: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    committed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    rolled_back_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ImportRow(Base):
    __tablename__ = "import_rows"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    batch_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("import_batches.id"), nullable=False
    )
    row_index: Mapped[int] = mapped_column(Integer, nullable=False)
    raw_data: Mapped[dict] = mapped_column(JSONB, nullable=False)
    parsed_data: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    transaction_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)


# ─── Audit ──────────────────────────────────────────────────────────────────

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    actor_type: Mapped[str] = mapped_column(String(16), nullable=False)  # user / ai / system / import
    actor_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    action: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(36), nullable=False)
    before_snapshot: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    after_snapshot: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    source_channel: Mapped[str | None] = mapped_column(String(32), nullable=True)
    source_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    tool_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    request_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# ─── MCP Undo ────────────────────────────────────────────────────────────────

class McpUndoAction(Base):
    __tablename__ = "mcp_undo_actions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    undo_token: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(36), nullable=False)
    action: Mapped[str] = mapped_column(String(32), nullable=False, default="create")
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="pending", index=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


# ─── MCP Capture Session ────────────────────────────────────────────────────

class McpCaptureSession(Base, TimestampMixin, RevisionMixin):
    __tablename__ = "mcp_capture_sessions"

    capture_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    original_text: Mapped[str] = mapped_column(Text, nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Shanghai")
    locale: Mapped[str] = mapped_column(String(16), nullable=False, default="zh-CN")
    actions: Mapped[list] = mapped_column(JSONB, nullable=False)
    requires_confirmation: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    committed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    session_status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    source_channel: Mapped[str] = mapped_column(String(32), nullable=False, default="cloud_mcp")
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    committed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    dismissed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class McpCaptureTurn(Base, TimestampMixin, RevisionMixin):
    __tablename__ = "mcp_capture_turns"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    capture_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    turn_index: Mapped[int] = mapped_column(Integer, nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="assistant")
    text: Mapped[str | None] = mapped_column(Text, nullable=True)
    asset_ids: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    asset_context: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    actions: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    selected_action_indexes: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    result_entities: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    undo_token: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    supersedes_turn_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    turn_status: Mapped[str] = mapped_column(String(20), nullable=False, default="parsed")
    source_channel: Mapped[str] = mapped_column(String(32), nullable=False, default="cloud_mcp")


# ─── Tombstone ──────────────────────────────────────────────────────────────

class Tombstone(Base):
    __tablename__ = "tombstones"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False, index=True)
    entity_type: Mapped[str] = mapped_column(String(32), nullable=False)
    entity_id: Mapped[str] = mapped_column(String(36), nullable=False)
    purged_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_revision: Mapped[int] = mapped_column(Integer, nullable=False)


# ─── v0.9.0 Account / Device / E2EE / AI Relay contracts ───────────────────

ACCOUNT_SCHEMA_VERSION = 1
DEVICE_PROTOCOL_VERSION = 1
ENCRYPTED_ENTITY_SCHEMA_VERSION = 1
AI_JOB_PROTOCOL_VERSION = 1


class Account(Base, TimestampMixin):
    """Cloud identity root.

    v0.9.0 keeps legacy business ``user_id`` values equal to ``Account.id``.
    Account authentication must never imply access to E2EE data keys.
    """

    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    phone_e164: Mapped[str] = mapped_column(String(32), unique=True, nullable=False, index=True)
    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    account_status: Mapped[str] = mapped_column(String(20), nullable=False, default="active")
    plan: Mapped[str] = mapped_column(String(32), nullable=False, default="demo")
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=ACCOUNT_SCHEMA_VERSION
    )


class AccountAuthCredential(Base, TimestampMixin):
    """Opaque authentication record; never a plaintext or replayable password equivalent."""

    __tablename__ = "account_auth_credentials"

    account_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("accounts.id"), primary_key=True
    )
    protocol: Mapped[str] = mapped_column(String(32), nullable=False, default="opaque")
    protocol_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    credential_record: Mapped[str] = mapped_column(Text, nullable=False)


class AccountKeyEnvelope(Base, TimestampMixin):
    """Server-blind wrapper around account key material, encoded as text-safe ciphertext."""

    __tablename__ = "account_key_envelopes"
    __table_args__ = (
        UniqueConstraint(
            "account_id",
            "envelope_type",
            "key_version",
            name="uq_account_key_envelope_version",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    account_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("accounts.id"), nullable=False, index=True
    )
    envelope_type: Mapped[str] = mapped_column(
        String(24), nullable=False, default="password"
    )
    key_version: Mapped[int] = mapped_column(Integer, nullable=False)
    encryption_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    nonce: Mapped[str] = mapped_column(Text, nullable=False)
    ciphertext: Mapped[str] = mapped_column(Text, nullable=False)


class Device(Base, TimestampMixin):
    """Account-owned routing identity. Private keys never enter this table."""

    __tablename__ = "devices"
    __table_args__ = (
        Index(
            "uq_devices_default_compute_node_per_account",
            "account_id",
            unique=True,
            postgresql_where=text("is_default_compute_node IS TRUE"),
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    account_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("accounts.id"), nullable=False, index=True
    )
    display_name: Mapped[str] = mapped_column(String(128), nullable=False)
    platform: Mapped[str] = mapped_column(String(32), nullable=False)
    public_key: Mapped[str] = mapped_column(Text, nullable=False)
    trust_state: Mapped[str] = mapped_column(String(16), nullable=False, default="pending")
    capabilities: Mapped[list] = mapped_column(JSONB, nullable=False, default=list)
    is_default_compute_node: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    key_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    protocol_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=DEVICE_PROTOCOL_VERSION
    )


class EncryptedEntity(Base, TimestampMixin):
    """Cloud-blind synchronized business entity envelope.

    ``user_id`` is the legacy business partition key and is canonically equal to
    the authenticated ``account_id`` for v0.9.0. It is never client-authoritative.
    """

    __tablename__ = "encrypted_entities"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("accounts.id"), nullable=False, index=True
    )
    entity_type: Mapped[str] = mapped_column(String(48), nullable=False, index=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    lifecycle_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="active"
    )
    key_version: Mapped[int] = mapped_column(Integer, nullable=False)
    encryption_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    schema_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=ENCRYPTED_ENTITY_SCHEMA_VERSION
    )
    nonce: Mapped[str] = mapped_column(Text, nullable=False)
    ciphertext: Mapped[str] = mapped_column(Text, nullable=False)


class AiJob(Base, TimestampMixin):
    """Encrypted device-to-device relay message; payload remains opaque to cloud."""

    __tablename__ = "ai_jobs"
    __table_args__ = (
        UniqueConstraint(
            "account_id",
            "source_device_id",
            "idempotency_key",
            name="uq_ai_job_idempotency",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    account_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("accounts.id"), nullable=False, index=True
    )
    source_device_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("devices.id"), nullable=False, index=True
    )
    target_device_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("devices.id"), nullable=False, index=True
    )
    message_type: Mapped[str] = mapped_column(String(16), nullable=False, default="request")
    correlation_id: Mapped[str | None] = mapped_column(String(36), nullable=True, index=True)
    idempotency_key: Mapped[str] = mapped_column(String(128), nullable=False)
    delivery_status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="queued", index=True
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    next_attempt_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    delivered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    attempt_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    protocol_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=AI_JOB_PROTOCOL_VERSION
    )
    encryption_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    nonce: Mapped[str] = mapped_column(Text, nullable=False)
    ciphertext: Mapped[str] = mapped_column(Text, nullable=False)


# ─── Legacy v0.8.x User/Auth compatibility ──────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    email: Mapped[str] = mapped_column(String(256), unique=True, nullable=False, index=True)
    hashed_password: Mapped[str] = mapped_column(String(256), nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )


class ApiToken(Base):
    __tablename__ = "api_tokens"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=new_uuid)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(128), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    is_revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
