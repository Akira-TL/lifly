from __future__ import annotations

from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import inspect

from app.db.models import Asset, LedgerTransaction, Memo, Task
from app.modules.imexport import exporter
from app.modules.imexport import router as imexport_router


def test_export_result_metadata_includes_contract_checksum_and_counts() -> None:
    content = b"id,amount\n1,12.50\n"
    result = exporter._result(
        "ledger_transactions",
        "csv",
        "text/csv",
        content,
        {"ledger_transactions": 1},
    )

    metadata = result.metadata()
    assert metadata["contract_version"] == "export.v0.5.6"
    assert metadata["entity_type"] == "ledger_transactions"
    assert metadata["format"] == "csv"
    assert metadata["media_type"] == "text/csv"
    assert metadata["filename"] == "lifly-export-ledger_transactions.csv"
    assert metadata["size_bytes"] == len(content)
    assert metadata["checksum_sha256"] == hashlib.sha256(content).hexdigest()
    assert metadata["counts"] == {"ledger_transactions": 1}


def test_export_dicts_strip_internal_sensitive_fields() -> None:
    tx = LedgerTransaction(
        id="tx_1",
        user_id="local-dev",
        direction="expense",
        amount=Decimal("12.50"),
        currency="CNY",
        account_id="account_1",
        category_id="category_1",
        merchant="便利店",
        note="早餐",
        occurred_at=datetime(2026, 6, 1, 8, 0, tzinfo=timezone.utc),
        source="import",
        import_batch_id="batch_1",
        source_capture_id="capture_1",
        status="active",
    )
    asset = Asset(
        id="asset_1",
        user_id="local-dev",
        kind="internal",
        asset_type="file",
        filename="demo.pdf",
        mime_type="application/pdf",
        size_bytes=100,
        sha256="secret_hash",
        storage_provider="local",
        storage_key="private/path/demo.pdf",
        visibility="private",
        sync_status="synced",
        status="active",
    )

    tx_data = exporter._ledger_export_dict(tx)
    asset_data = exporter._asset_export_dict(asset)

    assert "user_id" not in tx_data
    assert "source_capture_id" not in tx_data
    assert tx_data["amount"] == 12.5
    assert tx_data["source"] == "import"
    assert "user_id" not in asset_data
    assert "storage_key" not in asset_data
    assert "sha256" not in asset_data
    assert asset_data["filename"] == "demo.pdf"


def test_export_all_json_contains_core_sections_and_version() -> None:
    source = inspect.getsource(exporter._export_all_json)

    assert '"contract_version": EXPORT_CONTRACT_VERSION' in source
    assert '"memos"' in source
    assert '"ledger_transactions"' in source
    assert '"tasks"' in source
    assert '"assets"' in source
    assert "_memo_export_dict" in source
    assert "_ledger_export_dict" in source
    assert "_task_export_dict" in source
    assert "_asset_export_dict" in source


def test_supported_export_types_and_formats_are_explicit() -> None:
    assert exporter.SUPPORTED_EXPORT_ENTITY_TYPES == (
        "ledger_transactions",
        "memos",
        "tasks",
        "assets",
        "all",
    )

    source = inspect.getsource(exporter.build_export_result)
    assert '"ledger_transactions"' in source
    assert '"csv"' in source
    assert '"memos"' in source
    assert '"md"' in source
    assert '"tasks"' in source
    assert '"assets"' in source
    assert '"all"' in source


def test_export_routes_return_metadata_and_stream_headers() -> None:
    export_data_source = inspect.getsource(imexport_router.export_data)
    export_stream_source = inspect.getsource(imexport_router.export_stream)

    assert "build_export_result" in export_data_source
    assert "result.metadata()" in export_data_source
    assert "preview" in export_data_source
    assert "ValueError" in export_data_source
    assert "status_code=400" in export_data_source

    assert "build_export_result" in export_stream_source
    assert "result.media_type" in export_stream_source
    assert "result.filename" in export_stream_source
    assert "X-Lifly-Export-Contract" in export_stream_source
    assert "X-Lifly-Export-Checksum-SHA256" in export_stream_source
    assert "X-Lifly-Export-Size-Bytes" in export_stream_source


def test_memo_and_task_export_dicts_do_not_include_internal_user_id() -> None:
    memo = Memo(
        id="memo_1",
        user_id="local-dev",
        type="memo",
        title="标题",
        content_markdown="内容",
        tags=["tag"],
        mood="ok",
        source_capture_id="capture_1",
        status="active",
    )
    task = Task(
        id="task_1",
        user_id="local-dev",
        title="任务",
        description="说明",
        task_status="todo",
        priority="normal",
        source_capture_id="capture_2",
        status="active",
    )

    memo_data = exporter._memo_export_dict(memo)
    task_data = exporter._task_export_dict(task)

    assert "user_id" not in memo_data
    assert "source_capture_id" not in memo_data
    assert memo_data["title"] == "标题"
    assert "user_id" not in task_data
    assert "source_capture_id" not in task_data
    assert task_data["title"] == "任务"
