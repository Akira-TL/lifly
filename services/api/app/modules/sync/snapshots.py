from __future__ import annotations

from app.db.models import McpCaptureSession, McpCaptureTurn, Memo
from app.modules.memos.service import memo_to_response
from app.schemas.common import json_serialize


def memo_snapshot(memo: Memo) -> dict:
    return json_serialize(memo_to_response(memo).model_dump())


def capture_session_snapshot(session: McpCaptureSession) -> dict:
    return json_serialize(
        {
            "capture_id": session.capture_id,
            "user_id": session.user_id,
            "original_text": session.original_text,
            "timezone": session.timezone,
            "locale": session.locale,
            "actions": list(session.actions or []),
            "requires_confirmation": bool(session.requires_confirmation),
            "committed": bool(session.committed),
            "session_status": session.session_status,
            "source_channel": session.source_channel,
            "expires_at": session.expires_at,
            "committed_at": session.committed_at,
            "dismissed_at": session.dismissed_at,
            "revision": session.revision,
            "created_at": session.created_at,
            "updated_at": session.updated_at,
        }
    )


def capture_turn_snapshot(turn: McpCaptureTurn) -> dict:
    return json_serialize(
        {
            "id": turn.id,
            "user_id": turn.user_id,
            "capture_id": turn.capture_id,
            "turn_index": turn.turn_index,
            "role": turn.role,
            "text": turn.text,
            "asset_ids": list(turn.asset_ids or []),
            "asset_context": list(turn.asset_context or []),
            "actions": list(turn.actions or []),
            "selected_action_indexes": list(turn.selected_action_indexes or []),
            "result_entities": list(turn.result_entities or []),
            "undo_token": turn.undo_token,
            "supersedes_turn_id": turn.supersedes_turn_id,
            "turn_status": turn.turn_status,
            "source_channel": turn.source_channel,
            "revision": turn.revision,
            "created_at": turn.created_at,
            "updated_at": turn.updated_at,
        }
    )
