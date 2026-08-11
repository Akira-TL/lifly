from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
import inspect
from types import SimpleNamespace

import pytest

from app.db.models import ImportBatch, LedgerTransaction, Memo, Task, TaskReminderStrategy
from app.modules.search import router as search_router


def test_home_overview_route_is_cloud_primary_contract() -> None:
    source = inspect.getsource(search_router.home_overview)
    builder_source = inspect.getsource(search_router.build_home_overview)
    dashboard_source = inspect.getsource(search_router.dashboard)

    assert '@router.get("/home/overview"' in inspect.getsource(search_router)
    assert "build_home_overview" in source
    assert '"schema_version"' in builder_source
    assert '"source_mode"' in builder_source
    assert '"attention_items"' in builder_source
    assert '"today_metrics"' in builder_source
    assert '"finance_overview"' in builder_source
    assert '"budget_progress"' in builder_source
    assert '"category_breakdown"' in builder_source
    assert '"insights"' in builder_source
    assert '"recent_activity"' in builder_source
    assert '"sync_summary"' in builder_source
    assert "await _sync_summary" in builder_source
    assert "await _import_summary" in builder_source
    assert "_settings_summary()" in builder_source
    assert "build_home_overview" in dashboard_source


class _Result:
    def __init__(self, rows: list[object]) -> None:
        self._rows = rows

    def all(self) -> list[object]:
        return self._rows


class _SummaryDb:
    def __init__(self, *, rows: list[object] | None = None, scalar: object = None) -> None:
        self._rows = rows or []
        self._scalar = scalar

    async def execute(self, _statement: object) -> _Result:
        return _Result(self._rows)

    async def scalar(self, _statement: object) -> object:
        return self._scalar


@pytest.mark.anyio
async def test_home_overview_sync_summary_uses_real_asset_counts() -> None:
    db = _SummaryDb(
        rows=[
            SimpleNamespace(sync_status="pending", count=2),
            SimpleNamespace(sync_status="failed", count=1),
            SimpleNamespace(sync_status="synced", count=4),
        ]
    )

    summary = await search_router._sync_summary(db, "local-dev")

    assert summary["status"] == "error"
    assert summary["pending_asset_count"] == 2
    assert summary["failed_asset_count"] == 1
    assert summary["synced_asset_count"] == 4
    assert isinstance(summary["powersync_configured"], bool)


@pytest.mark.anyio
async def test_home_overview_import_summary_uses_latest_batch_fields() -> None:
    created_at = datetime(2026, 7, 11, 10, tzinfo=timezone.utc)
    batch = ImportBatch(
        id="batch-1",
        user_id="local-dev",
        source_provider="alipay",
        filename="alipay.csv",
        status="committed",
        total_rows=20,
        valid_rows=18,
        duplicate_rows=2,
        created_at=created_at,
        committed_at=created_at + timedelta(minutes=5),
    )

    summary = await search_router._import_summary(
        _SummaryDb(scalar=batch),
        "local-dev",
    )

    assert summary["status"] == "committed"
    assert summary["latest_batch_id"] == "batch-1"
    assert summary["source_provider"] == "alipay"
    assert summary["valid_rows"] == 18
    assert summary["committed_at"] is not None


def test_home_overview_settings_summary_exposes_readiness_without_secrets() -> None:
    summary = search_router._settings_summary()

    assert summary["status"] in {"ok", "attention"}
    assert summary["mode"] == "server"
    assert isinstance(summary["database_configured"], bool)
    assert isinstance(summary["powersync_configured"], bool)
    assert isinstance(summary["object_storage_configured"], bool)
    assert "database_url" not in summary
    assert "minio_secret_key" not in summary


def test_home_overview_attention_items_rank_by_quadrant_before_time_status() -> None:
    now = datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    overdue = Task(
        id="task-overdue",
        user_id="local-dev",
        title="逾期任务",
        due_at=now - timedelta(days=1),
        priority="normal",
        task_status="todo",
        status="active",
        updated_at=now - timedelta(days=1),
    )
    today = Task(
        id="task-today",
        user_id="local-dev",
        title="今天任务",
        due_at=now.replace(hour=18),
        priority="high",
        task_status="todo",
        status="active",
        updated_at=now,
    )

    strategy = TaskReminderStrategy(
        id="strategy-today",
        user_id="local-dev",
        task_id="task-today",
        warning_level="warning",
        warning_reason="AI 建议提前准备",
        strategy_status="suggested",
        source="ai",
        updated_at=now,
    )

    items = search_router._build_attention_items(
        [today, overdue],
        {"task-today": strategy},
        now,
    )

    assert [item["type"] for item in items] == ["task_warning_strategy", "task_overdue"]
    assert items[0]["quadrant"] == "important_urgent"
    assert items[0]["level"] == "critical"
    assert items[1]["quadrant"] == "not_important_urgent"
    assert items[1]["level"] == "warning"
    assert items[0]["entity_type"] == "task"


def test_home_overview_daily_trend_and_recent_activity_are_mixed() -> None:
    now = datetime(2026, 7, 7, 12, tzinfo=timezone.utc)
    memo = Memo(
        id="memo-1",
        user_id="local-dev",
        type="memo",
        title="本地备忘",
        content_markdown="最近内容",
        status="active",
        updated_at=now - timedelta(hours=1),
    )
    task = Task(
        id="task-1",
        user_id="local-dev",
        title="任务",
        due_at=now + timedelta(hours=3),
        task_status="todo",
        status="active",
        updated_at=now - timedelta(hours=2),
    )
    tx = LedgerTransaction(
        id="tx-1",
        user_id="local-dev",
        direction="expense",
        amount=Decimal("18.50"),
        currency="CNY",
        merchant="食堂",
        note="午餐",
        occurred_at=now,
        status="active",
    )

    trend = search_router._build_daily_trend([tx], now)
    activity = search_router._build_recent_activity([memo], [task], [tx])

    assert len(trend) == 7
    assert sum(item["total"] for item in trend) == 18.5
    assert {item["entity_type"] for item in activity} == {"memo", "task", "ledger_transaction"}
    ledger_item = next(item for item in activity if item["entity_type"] == "ledger_transaction")
    assert ledger_item["amount"] == 18.5
