from __future__ import annotations

import pytest

from app.db.models import Asset
from app.modules.mcp import capture_asset_context as asset_context


def _asset(**overrides: object) -> Asset:
    values: dict[str, object] = {
        "id": "asset-1",
        "user_id": "local-dev",
        "kind": "internal",
        "asset_type": "file",
        "filename": "notes.txt",
        "mime_type": "text/plain",
        "size_bytes": 32,
        "storage_provider": "minio",
        "storage_key": "attachments/local-dev/asset-1/notes.txt",
        "visibility": "private",
        "sync_status": "synced",
        "status": "active",
    }
    values.update(overrides)
    return Asset(**values)


@pytest.mark.anyio
async def test_plain_text_asset_is_extracted_and_composed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        asset_context,
        "read_object_bytes",
        lambda storage_key, max_bytes: "提醒我明天交房租".encode(),
    )

    context = await asset_context._resolve_asset_context(_asset())
    result = asset_context.CaptureAssetContextResult(contexts=[context])

    assert context.status == "ready"
    assert context.extractor == "plain_text"
    assert context.text == "提醒我明天交房租"
    assert "以下是用户附加的已提取内容" in asset_context.build_capture_parse_text(
        "分析附件",
        result,
    )


@pytest.mark.anyio
async def test_pdf_image_and_audio_report_required_capabilities() -> None:
    pdf = await asset_context._resolve_asset_context(
        _asset(asset_type="pdf", mime_type="application/pdf")
    )
    image = await asset_context._resolve_asset_context(
        _asset(asset_type="image", mime_type="image/png")
    )
    audio = await asset_context._resolve_asset_context(
        _asset(asset_type="audio", mime_type="audio/mpeg")
    )

    assert (pdf.status, pdf.required_capability) == (
        "unsupported",
        "pdf_text_extraction",
    )
    assert (image.status, image.required_capability) == (
        "unsupported",
        "ocr_or_vision",
    )
    assert (audio.status, audio.required_capability) == (
        "unsupported",
        "speech_to_text",
    )


@pytest.mark.anyio
async def test_external_and_pending_assets_do_not_fake_extracted_text() -> None:
    external = await asset_context._resolve_asset_context(
        _asset(
            kind="external",
            asset_type="link",
            mime_type=None,
            storage_key=None,
            external_url="https://example.com/article",
        )
    )
    pending = await asset_context._resolve_asset_context(
        _asset(sync_status="pending")
    )

    assert external.status == "metadata_only"
    assert external.text is None
    assert external.required_capability == "external_content_fetch"
    assert pending.status == "pending_upload"
    assert pending.text is None


@pytest.mark.anyio
async def test_text_extraction_reports_limits_encoding_and_storage_failures(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    too_large = await asset_context._resolve_asset_context(
        _asset(size_bytes=asset_context.MAX_CAPTURE_ASSET_BYTES + 1)
    )
    assert too_large.status == "unsupported"
    assert too_large.error == "asset_too_large"

    monkeypatch.setattr(
        asset_context,
        "read_object_bytes",
        lambda storage_key, max_bytes: b"\xff\xfe",
    )
    invalid_encoding = await asset_context._resolve_asset_context(_asset())
    assert invalid_encoding.status == "failed"
    assert invalid_encoding.error == "unsupported_text_encoding"

    def fail_storage(storage_key: str, max_bytes: int) -> bytes:
        raise RuntimeError("storage unavailable")

    monkeypatch.setattr(asset_context, "read_object_bytes", fail_storage)
    storage_failure = await asset_context._resolve_asset_context(_asset())
    assert storage_failure.status == "failed"
    assert storage_failure.error == "storage_read_failed:RuntimeError"


def test_combined_extracted_text_is_bounded() -> None:
    contexts = [
        asset_context.CaptureAssetContext(
            asset_id=f"asset-{index}",
            name=f"asset-{index}.txt",
            status="ready",
            extractor="plain_text",
            text="x" * asset_context.MAX_CAPTURE_ASSET_TEXT_CHARS,
        )
        for index in range(2)
    ]
    result = asset_context.CaptureAssetContextResult(contexts=contexts)

    extracted = result.extracted_text
    content_length = sum(
        len(section.split(":\n", 1)[1])
        for section in extracted.split("\n\n")
    )
    assert content_length == asset_context.MAX_COMBINED_ASSET_TEXT_CHARS


def test_asset_ids_are_deduplicated_without_reordering() -> None:
    assert asset_context.normalize_asset_ids(
        [" asset-a ", "asset-b", "asset-a", "", "asset-c"]
    ) == ["asset-a", "asset-b", "asset-c"]
