from __future__ import annotations

from dataclasses import dataclass, field

from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.modules.ledger.service import create_ledger_transaction_record
from app.modules.memos.service import create_memo_record
from app.modules.mcp.parse_engine import CandidateAction
from app.modules.tasks.service import create_task_record
from app.schemas.common import LedgerTransactionCreate, MemoCreate, TaskCreate


@dataclass
class CaptureCommitFailure:
    action_index: int
    action_type: str | None
    reason: str
    detail: object | None = None

    def to_dict(self) -> dict:
        result: dict = {
            "action_index": self.action_index,
            "action_type": self.action_type,
            "reason": self.reason,
        }
        if self.detail is not None:
            result["detail"] = self.detail
        return result


@dataclass
class CaptureCommitResult:
    created_entities: list[dict] = field(default_factory=list)
    failed_actions: list[CaptureCommitFailure] = field(default_factory=list)

    @property
    def committed(self) -> bool:
        return bool(self.created_entities) and not self.failed_actions


@dataclass
class IndexedCaptureAction:
    index: int
    action: CandidateAction


def select_capture_actions(
    actions: list[CandidateAction],
    selected_indexes: list[int] | None,
) -> tuple[list[IndexedCaptureAction], list[CaptureCommitFailure]]:
    if selected_indexes is None:
        return [IndexedCaptureAction(index=index, action=action) for index, action in enumerate(actions)], []

    selected: list[IndexedCaptureAction] = []
    failures: list[CaptureCommitFailure] = []
    seen: set[int] = set()

    for index in selected_indexes:
        if index in seen:
            failures.append(CaptureCommitFailure(index, None, "duplicate_action_index"))
            continue
        seen.add(index)

        if index < 0 or index >= len(actions):
            failures.append(CaptureCommitFailure(index, None, "action_index_out_of_range"))
            continue
        selected.append(IndexedCaptureAction(index=index, action=actions[index]))

    return selected, failures


async def commit_capture_actions(
    db: AsyncSession,
    *,
    capture_id: str,
    actions: list[CandidateAction],
    selected_indexes: list[int] | None,
    user_id: str,
    actor_type: str,
    source_channel: str,
    entity_source: str,
    source_text: str | None,
) -> CaptureCommitResult:
    selected_actions, failures = select_capture_actions(actions, selected_indexes)
    result = CaptureCommitResult(failed_actions=failures)

    for indexed in selected_actions:
        action = indexed.action
        payload = action.payload

        if action.type == "memo_create":
            try:
                data = MemoCreate.model_validate({
                    **payload,
                    "type": payload.get("type") or "memo",
                    "source": payload.get("source") or entity_source,
                    "source_capture_id": capture_id,
                })
            except ValidationError as exc:
                result.failed_actions.append(
                    CaptureCommitFailure(indexed.index, action.type, "validation_error", exc.errors())
                )
                continue

            memo = await create_memo_record(
                db,
                data,
                user_id=user_id,
                actor_type=actor_type,
                source_channel=source_channel,
                tool_name="capture_commit",
                source_text=source_text or action.raw_text,
            )
            result.created_entities.append({"type": "memo", "id": memo.id})
            continue

        if action.type == "expense_create":
            try:
                data = LedgerTransactionCreate.model_validate({
                    **payload,
                    "direction": payload.get("direction") or "expense",
                    "source": payload.get("source") or entity_source,
                    "source_capture_id": capture_id,
                    "confidence": payload.get("confidence") if payload.get("confidence") is not None else action.confidence,
                })
            except ValidationError as exc:
                result.failed_actions.append(
                    CaptureCommitFailure(indexed.index, action.type, "validation_error", exc.errors())
                )
                continue

            tx = await create_ledger_transaction_record(
                db,
                data,
                user_id=user_id,
                actor_type=actor_type,
                source_channel=source_channel,
                tool_name="capture_commit",
                source_text=source_text or action.raw_text,
            )
            result.created_entities.append({"type": "ledger_transaction", "id": tx.id})
            continue

        if action.type == "task_create":
            try:
                data = TaskCreate.model_validate({
                    **payload,
                    "source": payload.get("source") or entity_source,
                    "source_capture_id": capture_id,
                })
            except ValidationError as exc:
                result.failed_actions.append(
                    CaptureCommitFailure(indexed.index, action.type, "validation_error", exc.errors())
                )
                continue

            task = await create_task_record(
                db,
                data,
                user_id=user_id,
                actor_type=actor_type,
                source_channel=source_channel,
                tool_name="capture_commit",
                source_text=source_text or action.raw_text,
            )
            result.created_entities.append({"type": "task", "id": task.id})
            continue

        result.failed_actions.append(
            CaptureCommitFailure(indexed.index, action.type, "unsupported_action_type")
        )

    return result
