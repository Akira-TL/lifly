from __future__ import annotations

from datetime import datetime, timezone
import inspect

import pytest
from pydantic import ValidationError

from app.core import schema_compat
from app.db.models import LedgerBudget
from app.modules.ledger import router as ledger_router
from app.modules.ledger.service import ledger_budget_to_response
from app.schemas.common import LedgerBudgetCreate, LedgerBudgetUpdate


def test_ledger_budget_schema_validates_period_amount_and_threshold() -> None:
    valid = LedgerBudgetCreate(
        period_key="2026-07",
        category_id="food",
        amount=1200,
        alert_threshold=0.8,
    )
    assert valid.period_type == "month"
    assert valid.category_id == "food"

    with pytest.raises(ValidationError):
        LedgerBudgetCreate(period_key="2026-13", amount=100)
    with pytest.raises(ValidationError):
        LedgerBudgetCreate(period_key="2026-07", amount=0)
    with pytest.raises(ValidationError):
        LedgerBudgetCreate(period_key="2026-07", amount=100, alert_threshold=1.2)

    update = LedgerBudgetUpdate(category_id=None, amount=500)
    assert "category_id" in update.model_fields_set


def test_ledger_budget_response_exposes_revision_and_category_scope() -> None:
    now = datetime(2026, 7, 8, 9, tzinfo=timezone.utc)
    budget = LedgerBudget(
        id="budget-1",
        user_id="local-dev",
        period_type="month",
        period_key="2026-07",
        category_id="food",
        amount=1200,
        currency="CNY",
        alert_threshold=0.8,
        status="active",
        revision=2,
        created_at=now,
        updated_at=now,
    )

    response = ledger_budget_to_response(budget, category_name="餐饮")

    assert response.category_name == "餐饮"
    assert response.amount == 1200
    assert response.revision == 2


def test_ledger_budget_routes_cover_crud_conflict_and_audit() -> None:
    source = inspect.getsource(ledger_router)

    assert '@router.get("/budgets"' in source
    assert '@router.post("/budgets"' in source
    assert '@router.get("/budgets/{budget_id}"' in source
    assert '@router.put("/budgets/{budget_id}"' in source
    assert '@router.delete("/budgets/{budget_id}"' in source
    assert "_ensure_budget_identity_available" in source
    assert "Budget category must be an expense category" in source
    assert 'action="budget.create"' in source
    assert 'action="budget.delete"' in source
    assert 'entity_type="ledger_budget"' in source
    assert "budget.revision += 1" in source


def test_existing_database_budget_revision_is_hardened_additively() -> None:
    source = inspect.getsource(schema_compat.ensure_schema_compatibility)

    assert "ALTER TABLE ledger_budgets" in source
    assert "ADD COLUMN IF NOT EXISTS revision" in source
    assert "PRAGMA table_info(ledger_budgets)" in source
