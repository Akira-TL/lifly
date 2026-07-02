from __future__ import annotations

import inspect

from pydantic import ValidationError

from app.modules.mcp import capture_commit_service, router as mcp_router
from app.modules import trash
from app.schemas.common import MemoCreate


def test_capture_commit_has_batch_safety_limit() -> None:
    source = inspect.getsource(mcp_router.capture_commit)

    assert "MCP_MAX_CAPTURE_COMMIT_ACTIONS = 10" in inspect.getsource(mcp_router)
    assert "selected_count" in source
    assert "at most" in source
    assert "HTTPException" in source


def test_capture_commit_passes_request_id_to_audit_writes() -> None:
    router_source = inspect.getsource(mcp_router.capture_commit)
    service_source = inspect.getsource(capture_commit_service.commit_capture_actions)

    assert "request_id = _request_id(request, body)" in router_source
    assert "request_id=request_id" in router_source
    assert "request_id: str | None = None" in service_source
    assert service_source.count("request_id=request_id") == 3


def test_validation_error_detail_is_sanitized() -> None:
    try:
        MemoCreate.model_validate({"type": "memo", "content_markdown": 123})
    except ValidationError as exc:
        detail = capture_commit_service.sanitize_validation_errors(exc)
    else:  # pragma: no cover
        raise AssertionError("expected validation error")

    assert detail
    assert set(detail[0].keys()) <= {"loc", "msg", "type"}
    assert "input" not in detail[0]


def test_audit_api_supports_ai_write_filters_and_summary() -> None:
    audit_source = inspect.getsource(trash.list_audit_logs)
    summary_source = inspect.getsource(trash.ai_audit_summary)

    for field in ["actor_type", "source_channel", "tool_name", "request_id"]:
        assert field in audit_source
    assert "has_before_snapshot" in audit_source
    assert "has_after_snapshot" in audit_source
    assert "source_text" not in audit_source
    assert "AuditLog.actor_type == \"ai\"" in summary_source
    assert "group_by" in summary_source


def test_mcp_direct_writes_pass_request_id() -> None:
    handlers = [
        mcp_router.mcp_memo_create,
        mcp_router.mcp_expense_create,
        mcp_router.mcp_task_create,
        mcp_router.mcp_task_complete,
        mcp_router.mcp_asset_create_upload_url,
        mcp_router.mcp_asset_register_external_url,
    ]

    for handler in handlers:
        source = inspect.getsource(handler)
        assert "request_id=_request_id(request, body)" in source
