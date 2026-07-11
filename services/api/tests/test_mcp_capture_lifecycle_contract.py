from __future__ import annotations

import inspect

import pytest

from app.db.models import McpCaptureSession, McpCaptureTurn
from app.modules.mcp import capture_lifecycle_router
from app.modules.mcp.capture_schemas import (
    CaptureAppendTurnRequest,
    CaptureCommitRequest,
    CaptureReviseActionRequest,
)
from app.modules.mcp.capture_session_service import revise_capture_actions
from app.modules.mcp.parse_engine import CandidateAction


def test_capture_lifecycle_routes_and_models_exist() -> None:
    source = inspect.getsource(capture_lifecycle_router)

    assert '@router.get("/sessions")' in source
    assert '@router.get("/sessions/{capture_id}")' in source
    assert '@router.post("/sessions/{capture_id}/turns")' in source
    assert '@router.post("/sessions/{capture_id}/turns/{turn_id}/revise")' in source
    assert '@router.post("/sessions/{capture_id}/dismiss")' in source
    assert hasattr(McpCaptureSession, "revision")
    assert hasattr(McpCaptureTurn, "asset_ids")
    assert hasattr(McpCaptureTurn, "undo_token")
    assert hasattr(McpCaptureTurn, "supersedes_turn_id")
    assert hasattr(McpCaptureTurn, "revision")


def test_capture_requests_preserve_continuous_session_boundaries() -> None:
    append = CaptureAppendTurnRequest(text="继续设置下一条", asset_ids=["asset-1"])
    commit = CaptureCommitRequest(
        capture_id="capture-1",
        turn_id="turn-2",
        selected_action_indexes=[0],
    )
    revise = CaptureReviseActionRequest(
        action_index=0,
        payload={"title": "修改后的内容"},
        note="用户确认修改",
    )

    assert append.asset_ids == ["asset-1"]
    assert commit.turn_id == "turn-2"
    assert revise.payload == {"title": "修改后的内容"}


def test_capture_commit_rejects_duplicate_or_negative_indexes() -> None:
    with pytest.raises(ValueError):
        CaptureCommitRequest(
            capture_id="capture-1",
            selected_action_indexes=[0, 0],
        )
    with pytest.raises(ValueError):
        CaptureCommitRequest(
            capture_id="capture-1",
            selected_action_indexes=[-1],
        )


def test_revise_capture_action_replaces_only_selected_action() -> None:
    source = [
        CandidateAction(
            type="memo_create",
            payload={"title": "原始备忘"},
            confidence=0.7,
            raw_text="原始输入",
        ),
        CandidateAction(
            type="task_create",
            payload={"title": "原始任务"},
            confidence=0.8,
            raw_text="任务输入",
        ),
    ]

    revised = revise_capture_actions(
        source_actions=source,
        action_index=0,
        action_type="memo_create",
        payload={"title": "修改后的备忘"},
        confidence=0.95,
    )

    assert revised[0].payload == {"title": "修改后的备忘"}
    assert revised[0].confidence == 0.95
    assert revised[0].raw_text == "原始输入"
    assert revised[1] == source[1]
    assert source[0].payload == {"title": "原始备忘"}
