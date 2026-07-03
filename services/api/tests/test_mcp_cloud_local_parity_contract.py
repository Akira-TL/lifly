from __future__ import annotations

import inspect
import re
from pathlib import Path

from app.modules.mcp import cloud_server


FROZEN_TOOL_NAMES = [
    "capture_parse",
    "capture_commit",
    "capture_undo",
    "memo_create",
    "memo_search",
    "expense_create",
    "expense_search",
    "expense_summary",
    "task_create",
    "task_list",
    "task_complete",
    "asset_create_upload_url",
    "asset_register_external_url",
]

EXPECTED_INTERNAL_PATHS = {
    "capture_parse": "/api/v1/mcp/capture/parse",
    "capture_commit": "/api/v1/mcp/capture/commit",
    "capture_undo": "/api/v1/mcp/capture/undo",
    "memo_create": "/api/v1/mcp/memo/create",
    "memo_search": "/api/v1/mcp/memo/search",
    "expense_create": "/api/v1/mcp/expense/create",
    "expense_search": "/api/v1/mcp/expense/search",
    "expense_summary": "/api/v1/mcp/expense/summary",
    "task_create": "/api/v1/mcp/task/create",
    "task_list": "/api/v1/mcp/task/list",
    "task_complete": "/api/v1/mcp/task/complete",
    "asset_create_upload_url": "/api/v1/mcp/asset/create-upload-url",
    "asset_register_external_url": "/api/v1/mcp/asset/register-external-url",
}


def test_cloud_mcp_tool_order_matches_protocol() -> None:
    source = inspect.getsource(cloud_server)
    tool_names = re.findall(r'@cloud_mcp\.tool\(\s*name="([^"]+)"', source)

    assert tool_names == FROZEN_TOOL_NAMES


def test_cloud_mcp_tools_use_mcp_internal_routes() -> None:
    source = inspect.getsource(cloud_server)

    for tool_name, path in EXPECTED_INTERNAL_PATHS.items():
        function_source = inspect.getsource(getattr(cloud_server, tool_name))
        assert path in function_source
        assert "/api/v1/assets/" not in function_source

    assert "category_hint" in inspect.getsource(cloud_server.expense_create)
    assert "category_id" not in inspect.getsource(cloud_server.expense_create)
    assert source.count("/api/v1/mcp/") >= len(EXPECTED_INTERNAL_PATHS)


def test_local_mcp_uses_protocol_schema_for_every_tool() -> None:
    root = Path(__file__).resolve().parents[3]
    local_handlers = (root / "services/local-mcp/src/tool-handlers.ts").read_text(encoding="utf-8")

    for tool_name in FROZEN_TOOL_NAMES:
        assert f'case "{tool_name}"' in local_handlers
        assert f"LiflyMcpToolInputSchemas.{tool_name}.parse" in local_handlers

    assert "LiflyMcpToolNameSchema.options.map" in local_handlers
    assert "LiflyMcpToolDescriptions[name]" in local_handlers


def test_local_capture_output_fields_match_cloud_capture_contract() -> None:
    root = Path(__file__).resolve().parents[3]
    local_core = (root / "packages/local-core/src/types.ts").read_text(encoding="utf-8")
    fake_core = (root / "packages/local-core/src/fake-local-core.ts").read_text(encoding="utf-8")

    assert "failed_actions: LocalCaptureFailedAction[]" in local_core
    assert "entities: LocalCoreEntityRef[]" in local_core
    assert "failed_actions: failed" in fake_core
    assert "return { undone: 0, entities: [], failed_entities: [] }" in fake_core
    assert "duplicate_action_index" in fake_core
    assert "action_index_out_of_range" in fake_core
