from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import inspect

from app.db.models import ImportRow, LedgerTransaction
from app.modules.imexport import router as imexport_router


def test_import_commit_only_selects_committable_preview_rows() -> None:
    source = inspect.getsource(imexport_router.import_commit)

    assert "COMMITTABLE_IMPORT_ROW_STATUSES" in source
    assert "ImportRow.status.in_(COMMITTABLE_IMPORT_ROW_STATUSES)" in source
    assert "ignored" not in imexport_router.COMMITTABLE_IMPORT_ROW_STATUSES
    assert "error" not in imexport_router.COMMITTABLE_IMPORT_ROW_STATUSES
    assert "duplicate" not in imexport_router.COMMITTABLE_IMPORT_ROW_STATUSES


def test_import_commit_marks_transfer_and_invalid_rows_without_importing() -> None:
    source = inspect.getsource(imexport_router.import_commit)

    assert "direction not in" in source
    assert 'row.status = "ignored"' in source
    assert 'row.status = "error"' in source
    assert "Invalid amount" in source
    assert "Invalid occurred_at" in source


def test_import_commit_uses_provider_external_id_then_business_duplicate() -> None:
    source = inspect.getsource(imexport_router._should_mark_import_duplicate)
    external_source = inspect.getsource(imexport_router._has_external_import_duplicate)
    business_source = inspect.getsource(imexport_router._has_business_import_duplicate)

    assert "_has_external_import_duplicate" in source
    assert "_has_business_import_duplicate" in source
    assert 'parsed_data["external_id"]' in external_source
    assert "ImportBatch.source_provider" in external_source
    assert "ImportRow.transaction_id.is_not(None)" in external_source
    assert "LedgerTransaction.direction" in business_source
    assert "LedgerTransaction.amount" in business_source
    assert "LedgerTransaction.occurred_at" in business_source
    assert "LedgerTransaction.merchant" in business_source


def test_import_commit_writes_per_transaction_and_batch_audit() -> None:
    source = inspect.getsource(imexport_router.import_commit)

    assert "IMPORT_COMMIT_AUDIT_ACTION" in source
    assert '"ledger_transaction"' in source
    assert "_ledger_import_snapshot" in source
    assert "IMPORT_BATCH_COMMIT_AUDIT_ACTION" in source
    assert '"import_batch"' in source
    assert "source=\"import\"" in source


def test_import_helpers_normalize_amount_date_and_note() -> None:
    assert imexport_router._parse_import_amount("3.795") == Decimal("3.80")
    assert imexport_router._parse_import_amount("0") is None
    assert imexport_router._parse_import_amount(None) is None

    dt = imexport_router._parse_import_occurred_at("2026-06-28T10:52:05+00:00")
    assert dt == datetime(2026, 6, 28, 10, 52, 5, tzinfo=timezone.utc)
    assert imexport_router._parse_import_occurred_at("bad") is None

    note = imexport_router._build_import_note({
        "note": "洗衣机",
        "category_hint": "商户消费",
        "account_hint": "零钱",
        "source_provider": "wechat",
        "external_id": "tx_1",
    })
    assert note == "洗衣机 | 商户消费 | 零钱 | wechat | tx_1"


def test_ledger_import_snapshot_keeps_source_metadata() -> None:
    tx = LedgerTransaction(
        id="tx_1",
        user_id="local-dev",
        direction="expense",
        amount=Decimal("3.79"),
        currency="CNY",
        merchant="湖北笑联科技有限公司",
        note="洗衣机 | 商户消费 | 零钱 | wechat | external_1",
        occurred_at=datetime(2026, 6, 28, 10, 52, 5, tzinfo=timezone.utc),
        source="import",
        import_batch_id="batch_1",
        status="active",
    )
    row = ImportRow(
        id="row_1",
        batch_id="batch_1",
        row_index=0,
        raw_data={},
        parsed_data={},
        status="imported",
        transaction_id="tx_1",
    )
    snapshot = imexport_router._ledger_import_snapshot(
        tx,
        row=row,
        parsed={
            "source_provider": "wechat",
            "external_id": "external_1",
            "category_hint": "商户消费",
            "account_hint": "零钱",
        },
    )

    assert snapshot["import_batch_id"] == "batch_1"
    assert snapshot["import_row_id"] == "row_1"
    assert snapshot["source_provider"] == "wechat"
    assert snapshot["external_id"] == "external_1"
    assert snapshot["category_hint"] == "商户消费"
    assert snapshot["account_hint"] == "零钱"
