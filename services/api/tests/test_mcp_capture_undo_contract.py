from __future__ import annotations

import inspect

from app.modules.mcp import router as mcp_router
from app.modules.mcp import undo_service


def test_capture_undo_is_idempotent_for_used_tokens() -> None:
    source = inspect.getsource(mcp_router.capture_undo)

    assert "list_undo_entries" in source
    assert 'statuses=["used"]' in source
    assert 'return {"undone": 0, "entities": [], "failed_entities": []}' in source
    assert "Undo token not found or expired" in source


def test_capture_undo_supports_asset_ai_trash() -> None:
    source = inspect.getsource(mcp_router.capture_undo)

    assert '"asset": Asset' in source
    assert 'entity.status = "ai_trashed"' in source
    assert "asset_to_dict(entity)" in source
    assert '"undo_delete"' in source
    assert 'tool_name="capture_undo"' in source


def test_direct_asset_writes_persist_undo_entries() -> None:
    upload_source = inspect.getsource(mcp_router.mcp_asset_create_upload_url)
    external_source = inspect.getsource(mcp_router.mcp_asset_register_external_url)

    for source, tool_name in [
        (upload_source, "asset_create_upload_url"),
        (external_source, "asset_register_external_url"),
    ]:
        assert f'tool_name="{tool_name}"' in source
        assert "undo_token = str(uuid.uuid4())" in source
        assert 'created_entities=[{"type": "asset", "id": asset.id}]' in source
        assert '"undo_token": undo_token' in source


def test_undo_service_can_query_used_entries_for_idempotency() -> None:
    source = inspect.getsource(undo_service.list_undo_entries)
    consume_source = inspect.getsource(undo_service.consume_undo_entries)

    assert "statuses: list[str] | None = None" in source
    assert "McpUndoAction.status.in_(statuses)" in source
    assert "list_undo_entries" in consume_source
    assert 'statuses=["pending"]' in consume_source
