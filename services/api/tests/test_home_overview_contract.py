from __future__ import annotations

from datetime import datetime, timedelta, timezone
from decimal import Decimal
import inspect

from app.db.models import LedgerTransaction, Memo, Task
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
    assert '"recent_activity"' in builder_source
    assert '"sync_summary"' in builder_source
    assert "build_home_overview" in dashboard_source


def test_home_overview_attention_items_prioritize_overdue_then_today() -> None:
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

    items = search_router._build_attention_items([today, overdue], now)

    assert [item["type"] for item in items] == ["task_overdue", "task_due_today"]
    assert items[0]["level"] == "critical"
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
