from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import inspect

from app.db.models import ImportRow, LedgerTransaction
from app.modules.imexport import router as imexport_router


def test_import_rollback_rejects_duplicate_and_non_committed_batches() -> None:
    source = inspect.getsource(imexport_router.import_rollback)

    assert 'batch.status == "rolled_back"' in source
    assert "already been rolled back" in source
    assert 'batch.status != "committed"' in source
    assert "expected committed" in source


def test_import_rollback_only_selects_imported_rows_with_transactions() -> None:
    source = inspect.getsource(imexport_router.import_rollback)

    assert "IMPORT_ROW_IMPORTED_STATUS" in source
    assert "ImportRow.transaction_id.is_not(None)" in source
    assert "order_by(ImportRow.row_index)" in source
    assert "ignored" not in imexport_router.IMPORT_ROW_IMPORTED_STATUS
    assert "error" not in imexport_router.IMPORT_ROW_IMPORTED_STATUS


def test_import_rollback_soft_deletes_transactions_and_updates_rows() -> None:
    source = inspect.getsource(imexport_router.import_rollback)

    assert 'tx.status = "user_trashed"' in source
    assert "tx.deleted_at = now" in source
    assert "tx.revision += 1" in source
    assert "row.status = IMPORT_ROW_ROLLED_BACK_STATUS" in source
    assert 'row.status = "rollback_skipped"' in source
    assert "await db.delete" not in source
    assert "db.delete(" not in source


def test_import_rollback_writes_per_transaction_and_batch_audit() -> None:
    source = inspect.getsource(imexport_router.import_rollback)

    assert "IMPORT_ROLLBACK_AUDIT_ACTION" in source
    assert '"ledger_transaction"' in source
    assert "before=before_tx" in source
    assert "after=after_tx" in source
    assert "IMPORT_BATCH_ROLLBACK_AUDIT_ACTION" in source
    assert '"import_batch"' in source
    assert "before=before_batch" in source
    assert "after=after_batch" in source
    assert "source=\"import\"" in source


def test_import_row_status_constants_fit_model_limit() -> None:
    assert imexport_router.IMPORT_ROW_IMPORTED_STATUS == "imported"
    assert imexport_router.IMPORT_ROW_ROLLED_BACK_STATUS == "rolled_back"
    assert len("rollback_skipped") <= 16


def test_rollback_snapshot_contains_deleted_at_revision_and_row_metadata() -> None:
    tx = LedgerTransaction(
        id="tx_rollback_1",
        user_id="local-dev",
        direction="expense",
        amount=Decimal("12.50"),
        currency="CNY",
        merchant="便利店",
        note="早餐 | 餐饮 | 支付宝 | external_1",
        occurred_at=datetime(2026, 6, 1, 8, 0, tzinfo=timezone.utc),
        source="import",
        import_batch_id="batch_rollback_1",
        status="user_trashed",
        deleted_at=datetime(2026, 7, 4, 1, 0, tzinfo=timezone.utc),
        revision=2,
    )
    row = ImportRow(
        id="row_rollback_1",
        batch_id="batch_rollback_1",
        row_index=7,
        raw_data={},
        parsed_data={},
        status="rolled_back",
        transaction_id="tx_rollback_1",
    )

    snapshot = imexport_router._ledger_import_snapshot(
        tx,
        row=row,
        parsed={
            "source_provider": "alipay",
            "external_id": "external_1",
            "category_hint": "餐饮",
            "account_hint": "花呗",
        },
    )

    assert snapshot["status"] == "user_trashed"
    assert snapshot["deleted_at"] == "2026-07-04T01:00:00+00:00"
    assert snapshot["revision"] == 2
    assert snapshot["import_row_id"] == "row_rollback_1"
    assert snapshot["row_index"] == 7
    assert snapshot["source_provider"] == "alipay"
    assert snapshot["external_id"] == "external_1"
