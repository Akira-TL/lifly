from __future__ import annotations

import inspect

import pytest
from pydantic import ValidationError

from app.db.models import McpCaptureSession, McpCaptureTurn
from app.modules.mcp import router as mcp_router
from app.modules.mcp.capture_schemas import CaptureParseRequest
from app.modules.mcp.capture_session_service import (
    CAPTURE_SESSION_TTL,
    deserialize_capture_actions,
    serialize_capture_actions,
)
from app.modules.mcp.parse_engine import CandidateAction


class FakeDb:
    def __init__(self) -> None:
        self.added: list[object] = []
        self.flushed = False
        self.committed = False

    def add(self, value: object) -> None:
        self.added.append(value)

    async def flush(self) -> None:
        self.flushed = True

    async def commit(self) -> None:
        self.committed = True


@pytest.mark.anyio
async def test_capture_parse_persists_session_metadata() -> None:
    db = FakeDb()
    response = await mcp_router.capture_parse(
        CaptureParseRequest(
            text="记一下今天状态不错，提醒我晚上8点复盘",
            timezone="Asia/Shanghai",
            locale="zh-CN",
            asset_ids=["asset-1"],
        ),
        db,  # type: ignore[arg-type]
    )

    assert response["capture_id"]
    assert response["actions"]
    assert db.flushed is True
    assert db.committed is True
    assert len(db.added) == 3

    session = db.added[0]
    user_turn = db.added[1]
    action_turn = db.added[2]
    assert isinstance(session, McpCaptureSession)
    assert session.capture_id == response["capture_id"]
    assert session.user_id == mcp_router.DEFAULT_LOCAL_USER_ID
    assert session.original_text.startswith("记一下今天状态不错")
    assert session.timezone == "Asia/Shanghai"
    assert session.locale == "zh-CN"
    assert session.source_channel == mcp_router.CLOUD_MCP_SOURCE_CHANNEL
    assert session.committed is False
    assert session.expires_at is not None
    assert len(session.actions) == len(response["actions"])
    assert session.session_status == "active"

    assert isinstance(user_turn, McpCaptureTurn)
    assert user_turn.capture_id == response["capture_id"]
    assert user_turn.turn_index == 0
    assert user_turn.role == "user"
    assert user_turn.turn_status == "accepted"
    assert user_turn.text.startswith("记一下今天状态不错")
    assert user_turn.asset_ids == ["asset-1"]

    assert isinstance(action_turn, McpCaptureTurn)
    assert action_turn.id == response["turn_id"]
    assert action_turn.turn_index == 1
    assert action_turn.role == "assistant"
    assert action_turn.turn_status == "parsed"
    assert action_turn.asset_ids == ["asset-1"]
    assert len(action_turn.actions) == len(response["actions"])
    memo_actions = [
        action for action in action_turn.actions if action["type"] == "memo_create"
    ]
    assert memo_actions
    assert memo_actions[0]["payload"]["asset_ids"] == ["asset-1"]


def test_capture_parse_rejects_empty_text() -> None:
    with pytest.raises(ValidationError):
        CaptureParseRequest(text="   ")


def test_capture_action_serialization_roundtrip() -> None:
    actions = [
        CandidateAction(
            type="memo_create",
            payload={"type": "memo", "content_markdown": "hello"},
            confidence=0.75,
            raw_text="hello",
        )
    ]

    serialized = serialize_capture_actions(actions)
    restored = deserialize_capture_actions(serialized)

    assert serialized == [
        {
            "type": "memo_create",
            "payload": {"type": "memo", "content_markdown": "hello"},
            "confidence": 0.75,
            "raw_text": "hello",
        }
    ]
    assert restored == actions
    assert CAPTURE_SESSION_TTL.days == 30


def test_capture_commit_uses_persistent_session_before_memory_fallback() -> None:
    source = inspect.getsource(mcp_router.capture_commit)

    assert "get_active_capture_session" in source
    assert "deserialize_capture_actions" in source
    assert "mark_capture_session_committed" in source
    assert "mark_capture_turn_committed" in source
    assert "latest_action_turn" in source
    assert "memory_session = CAPTURE_STORE.get(capture_id)" in source
    assert source.index("get_active_capture_session") < source.index("memory_session")
