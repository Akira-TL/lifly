from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import inspect

from app.db.models import LedgerBudget
from app.modules.ledger import router as ledger_router


def test_ledger_budget_model_and_routes_exist() -> None:
    router_source = inspect.getsource(ledger_router)

    assert LedgerBudget.__tablename__ == "ledger_budgets"
    assert "LedgerBudget" in router_source
    assert '@router.get("/overview"' in router_source
    assert '@router.get("/categories/summary"' in router_source
    assert '@router.get("/insights"' in router_source
    assert "budget_state" in router_source
    assert "not_configured" in router_source


def test_period_range_normalizes_current_month_and_explicit_period() -> None:
    period_key, start, end = ledger_router._period_range("2026-07")

    assert period_key == "2026-07"
    assert start == datetime(2026, 7, 1, tzinfo=timezone.utc)
    assert end == datetime(2026, 8, 1, tzinfo=timezone.utc)


def test_ledger_insights_do_not_fake_budget() -> None:
    insights = ledger_router._ledger_insights_from_overview({
        "budget_state": "not_configured",
        "budget_progress": None,
    })

    assert insights[0]["id"] == "budget_not_configured"
    assert insights[0]["level"] == "info"


def test_ledger_insights_warn_when_budget_progress_is_high() -> None:
    insights = ledger_router._ledger_insights_from_overview({
        "budget_state": "configured",
        "budget_progress": 0.85,
    })

    assert insights[0]["id"] == "budget_progress_warning"
    assert insights[0]["level"] == "warning"


def test_ledger_budget_accepts_decimal_amount() -> None:
    budget = LedgerBudget(
        id="budget-1",
        user_id="local-dev",
        period_type="month",
        period_key="2026-07",
        category_id=None,
        amount=Decimal("1000.00"),
        currency="CNY",
        status="active",
    )

    assert budget.period_key == "2026-07"
    assert budget.category_id is None
    assert budget.amount == Decimal("1000.00")
