from __future__ import annotations

import inspect

from app.db.models import MemoClassification, TagMetadata
from app.modules.memos import router as memo_router
from app.modules.search import router as search_router


def test_memo_classification_models_exist() -> None:
    assert MemoClassification.__tablename__ == "memo_classifications"
    assert TagMetadata.__tablename__ == "tag_metadata"

    classification = MemoClassification(
        id="cls-1",
        user_id="local-dev",
        memo_id="memo-1",
        tag="读书",
        source="ai",
        status="suggested",
        confidence=0.8,
    )
    metadata = TagMetadata(
        id="tag-1",
        user_id="local-dev",
        name="读书",
        kind="memo",
        color_token="blue",
        icon_token="book",
        status="active",
    )

    assert classification.tag == "读书"
    assert classification.status == "suggested"
    assert metadata.kind == "memo"


def test_memo_classification_routes_and_boundaries_exist() -> None:
    source = inspect.getsource(memo_router)

    assert '@router.get("/{memo_id}/classifications"' in source
    assert '@router.post("/{memo_id}/classifications/confirm"' in source
    assert '@router.post("/{memo_id}/classifications/reject"' in source
    assert "tag is required" in source
    assert "confirmed_at" in source
    assert "Memo.tags" not in source


def test_tag_summary_route_excludes_rejected_classifications() -> None:
    source = inspect.getsource(search_router.tag_summary)

    assert '@router.get("/tags/summary"' in inspect.getsource(search_router)
    assert "MemoClassification.status != \"rejected\"" in source
    assert "confirmed_count" in source
    assert "suggested_count" in source
    assert "TagMetadata" in source
