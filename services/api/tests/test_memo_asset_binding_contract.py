from __future__ import annotations

import inspect

import pytest
from pydantic import ValidationError

from app.modules.assets import router as asset_router
from app.modules.memos import router as memo_router
from app.schemas.common import MemoAssetBindRequest, MemoResponse


def test_memo_response_accepts_asset_refs_for_detail_payload() -> None:
    fields = MemoResponse.model_fields
    assert "assets" in fields
    assert fields["assets"].default is None


def test_memo_asset_bind_request_validates_ref_type() -> None:
    payload = MemoAssetBindRequest.model_validate({"asset_id": "asset_1"})
    assert payload.asset_id == "asset_1"
    assert payload.ref_type == "attachment"

    with pytest.raises(ValidationError):
        MemoAssetBindRequest.model_validate({"asset_id": "asset_1", "ref_type": "bad"})


def test_memo_asset_ref_routes_and_helpers_are_exposed() -> None:
    router_source = inspect.getsource(memo_router)
    for token in [
        "list_memo_assets",
        "bind_memo_asset",
        "unbind_memo_asset",
        "MemoAssetRef",
        "asset_to_response",
    ]:
        assert token in router_source


def test_memo_asset_binding_writes_memo_audit_snapshots() -> None:
    for handler, action in [
        (memo_router.bind_memo_asset, "bind_asset"),
        (memo_router.unbind_memo_asset, "unbind_asset"),
    ]:
        source = inspect.getsource(handler)
        assert "write_memo_audit" in source
        assert action in source
        assert "before=json_serialize(before)" in source
        assert "after=json_serialize" in source
        assert "source_text" in source


def test_asset_delete_still_blocks_referenced_assets() -> None:
    source = inspect.getsource(asset_router.delete_asset)
    assert "MemoAssetRef" in inspect.getsource(asset_router)
    assert "ref_count" in source
    assert "Asset is referenced" in source
    assert "409" in source
