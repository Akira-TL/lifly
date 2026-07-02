from __future__ import annotations

import inspect

from app.modules.mcp import capture_commit_service, router as mcp_router


DIRECT_WRITE_HANDLERS = [
    (mcp_router.mcp_memo_create, "memo_create"),
    (mcp_router.mcp_expense_create, "expense_create"),
    (mcp_router.mcp_task_create, "task_create"),
    (mcp_router.mcp_task_complete, "task_complete"),
    (mcp_router.mcp_asset_create_upload_url, "asset_create_upload_url"),
    (mcp_router.mcp_asset_register_external_url, "asset_register_external_url"),
]


def test_cloud_mcp_write_context_constants() -> None:
    assert mcp_router.CLOUD_MCP_SOURCE_CHANNEL == "cloud_mcp"
    assert mcp_router.MCP_AI_ACTOR_TYPE == "ai"
    assert mcp_router.MCP_ENTITY_SOURCE == "ai"


def test_direct_cloud_mcp_write_handlers_use_cloud_source_context() -> None:
    for handler, tool_name in DIRECT_WRITE_HANDLERS:
        source = inspect.getsource(handler)

        assert "actor_type=MCP_AI_ACTOR_TYPE" in source
        assert "source_channel=CLOUD_MCP_SOURCE_CHANNEL" in source
        assert f'tool_name="{tool_name}"' in source
        assert 'source_channel="mcp"' not in source
        assert 'actor_type="ai"' not in source


def test_capture_commit_passes_cloud_source_context_to_commit_service() -> None:
    source = inspect.getsource(mcp_router.capture_commit)

    assert "commit_capture_actions" in source
    assert "actor_type=MCP_AI_ACTOR_TYPE" in source
    assert "source_channel=CLOUD_MCP_SOURCE_CHANNEL" in source
    assert "entity_source=MCP_ENTITY_SOURCE" in source
    assert 'source_channel="mcp"' not in source
    assert 'actor_type="ai"' not in source


def test_capture_commit_service_uses_capture_commit_tool_name_for_all_entity_writes() -> None:
    source = inspect.getsource(capture_commit_service.commit_capture_actions)

    assert source.count('tool_name="capture_commit"') == 3
    assert 'source_channel="mcp"' not in source
    assert 'actor_type="ai"' not in source


def test_undo_audit_defaults_to_cloud_source_context() -> None:
    source = inspect.getsource(mcp_router._write_audit)

    assert "source: str | None = CLOUD_MCP_SOURCE_CHANNEL" in source
    assert "actor_type=MCP_AI_ACTOR_TYPE" in source
    assert 'source_channel="mcp"' not in source
    assert 'actor_type="ai"' not in source
