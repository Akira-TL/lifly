from __future__ import annotations

import inspect

from app.modules.mcp import router as mcp_router
from app.modules.mcp.capture_commit_service import (
    CaptureCommitFailure,
    select_capture_actions,
)
from app.modules.mcp.parse_engine import CandidateAction


def _memo_action(text: str = "hello") -> CandidateAction:
    return CandidateAction(
        type="memo_create",
        payload={"type": "memo", "content_markdown": text},
        confidence=0.8,
        raw_text=text,
    )


def _task_action(title: str = "买猫粮") -> CandidateAction:
    return CandidateAction(
        type="task_create",
        payload={"title": title, "priority": "normal"},
        confidence=0.8,
        raw_text=title,
    )


def test_select_capture_actions_defaults_to_all_actions() -> None:
    actions = [_memo_action("a"), _task_action("b")]

    selected, failures = select_capture_actions(actions, None)

    assert failures == []
    assert [item.index for item in selected] == [0, 1]
    assert [item.action for item in selected] == actions


def test_select_capture_actions_supports_partial_submit() -> None:
    actions = [_memo_action("a"), _task_action("b"), _memo_action("c")]

    selected, failures = select_capture_actions(actions, [2, 0])

    assert failures == []
    assert [item.index for item in selected] == [2, 0]
    assert [item.action.raw_text for item in selected] == ["c", "a"]


def test_select_capture_actions_reports_invalid_and_duplicate_indexes() -> None:
    actions = [_memo_action("a")]

    selected, failures = select_capture_actions(actions, [0, 0, 2])

    assert [item.index for item in selected] == [0]
    assert [failure.to_dict() for failure in failures] == [
        {"action_index": 0, "action_type": None, "reason": "duplicate_action_index"},
        {"action_index": 2, "action_type": None, "reason": "action_index_out_of_range"},
    ]


def test_capture_commit_failure_serializes_optional_detail() -> None:
    failure = CaptureCommitFailure(1, "task_create", "validation_error", [{"msg": "bad"}])

    assert failure.to_dict() == {
        "action_index": 1,
        "action_type": "task_create",
        "reason": "validation_error",
        "detail": [{"msg": "bad"}],
    }


def test_router_capture_commit_uses_commit_service() -> None:
    source = inspect.getsource(mcp_router.capture_commit)

    assert "commit_capture_actions" in source
    assert "failed_actions" in source
    assert "selected_indexes=selected_indexes" in source
    assert "create_memo_record" not in source
    assert "create_ledger_transaction_record" not in source
    assert "create_task_record" not in source
