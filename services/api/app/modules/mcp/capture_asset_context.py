from __future__ import annotations

import asyncio
from collections.abc import Iterable
from typing import Literal

from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.storage import read_object_bytes
from app.db.models import Asset

CaptureAssetStatus = Literal[
    "ready",
    "metadata_only",
    "pending_upload",
    "unsupported",
    "missing",
    "inactive",
    "failed",
]

TEXT_MIME_TYPES = {
    "text/plain",
    "text/markdown",
    "text/csv",
    "application/json",
    "application/xml",
}
MAX_CAPTURE_ASSET_BYTES = 256 * 1024
MAX_CAPTURE_ASSET_TEXT_CHARS = 20_000
MAX_COMBINED_ASSET_TEXT_CHARS = 30_000


class CaptureAssetContext(BaseModel):
    asset_id: str
    kind: str | None = None
    asset_type: str | None = None
    name: str | None = None
    mime_type: str | None = None
    size_bytes: int | None = None
    source_url: str | None = None
    status: CaptureAssetStatus
    extractor: str
    text: str | None = None
    error: str | None = None
    required_capability: str | None = None
    metadata: dict[str, str | int | bool | None] = Field(default_factory=dict)


class CaptureAssetContextResult(BaseModel):
    contexts: list[CaptureAssetContext] = Field(default_factory=list)

    @property
    def extracted_text(self) -> str:
        sections: list[str] = []
        used = 0
        for context in self.contexts:
            if context.status != "ready" or not context.text:
                continue
            remaining = MAX_COMBINED_ASSET_TEXT_CHARS - used
            if remaining <= 0:
                break
            text = context.text[:remaining]
            sections.append(f"附件 {context.name or context.asset_id}:\n{text}")
            used += len(text)
        return "\n\n".join(sections)


def normalize_asset_ids(asset_ids: Iterable[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()
    for asset_id in asset_ids:
        value = asset_id.strip()
        if not value or value in seen:
            continue
        seen.add(value)
        normalized.append(value)
    return normalized


async def resolve_capture_asset_contexts(
    db: AsyncSession,
    *,
    asset_ids: list[str],
    user_id: str,
) -> CaptureAssetContextResult:
    normalized_ids = normalize_asset_ids(asset_ids)
    if not normalized_ids:
        return CaptureAssetContextResult()

    result = await db.execute(
        select(Asset).where(
            Asset.user_id == user_id,
            Asset.id.in_(normalized_ids),
        )
    )
    by_id = {asset.id: asset for asset in result.scalars().all()}

    contexts: list[CaptureAssetContext] = []
    for asset_id in normalized_ids:
        asset = by_id.get(asset_id)
        if asset is None:
            contexts.append(
                CaptureAssetContext(
                    asset_id=asset_id,
                    status="missing",
                    extractor="none",
                    error="asset_not_found",
                )
            )
            continue
        contexts.append(await _resolve_asset_context(asset))
    return CaptureAssetContextResult(contexts=contexts)


async def _resolve_asset_context(asset: Asset) -> CaptureAssetContext:
    base = _base_context(asset)
    if asset.status != "active":
        return base.model_copy(
            update={
                "status": "inactive",
                "error": f"asset_status_{asset.status}",
            }
        )

    if asset.kind == "external":
        return base.model_copy(
            update={
                "extractor": "external_reference",
                "required_capability": "external_content_fetch",
            }
        )

    if asset.sync_status != "synced":
        return base.model_copy(
            update={
                "status": "pending_upload",
                "error": f"asset_sync_status_{asset.sync_status}",
            }
        )

    mime_type = (asset.mime_type or "").split(";", 1)[0].strip().lower()
    if mime_type in TEXT_MIME_TYPES:
        return await _extract_text_asset(asset, base)
    if mime_type == "application/pdf" or asset.asset_type == "pdf":
        return base.model_copy(
            update={
                "status": "unsupported",
                "extractor": "pdf_adapter",
                "required_capability": "pdf_text_extraction",
            }
        )
    if mime_type.startswith("image/") or asset.asset_type == "image":
        return base.model_copy(
            update={
                "status": "unsupported",
                "extractor": "image_adapter",
                "required_capability": "ocr_or_vision",
            }
        )
    if mime_type.startswith("audio/") or asset.asset_type == "audio":
        return base.model_copy(
            update={
                "status": "unsupported",
                "extractor": "audio_adapter",
                "required_capability": "speech_to_text",
            }
        )
    return base.model_copy(
        update={"required_capability": "binary_content_extractor"}
    )


async def _extract_text_asset(
    asset: Asset,
    base: CaptureAssetContext,
) -> CaptureAssetContext:
    if not asset.storage_key:
        return base.model_copy(
            update={
                "status": "failed",
                "extractor": "plain_text",
                "error": "missing_storage_key",
            }
        )
    if asset.size_bytes is not None and asset.size_bytes > MAX_CAPTURE_ASSET_BYTES:
        return base.model_copy(
            update={
                "status": "unsupported",
                "extractor": "plain_text",
                "error": "asset_too_large",
                "required_capability": "large_text_streaming",
            }
        )
    try:
        payload = await asyncio.to_thread(
            read_object_bytes,
            asset.storage_key,
            MAX_CAPTURE_ASSET_BYTES,
        )
        text = payload.decode("utf-8-sig").strip()
    except UnicodeDecodeError:
        return base.model_copy(
            update={
                "status": "failed",
                "extractor": "plain_text",
                "error": "unsupported_text_encoding",
            }
        )
    except ValueError:
        return base.model_copy(
            update={
                "status": "unsupported",
                "extractor": "plain_text",
                "error": "asset_too_large",
                "required_capability": "large_text_streaming",
            }
        )
    except Exception as exc:  # storage diagnostics are persisted as context, not leaked
        return base.model_copy(
            update={
                "status": "failed",
                "extractor": "plain_text",
                "error": f"storage_read_failed:{type(exc).__name__}",
            }
        )
    return base.model_copy(
        update={
            "status": "ready",
            "extractor": "plain_text",
            "text": text[:MAX_CAPTURE_ASSET_TEXT_CHARS],
            "metadata": {
                **base.metadata,
                "truncated": len(text) > MAX_CAPTURE_ASSET_TEXT_CHARS,
            },
        }
    )


def build_capture_parse_text(
    user_text: str,
    result: CaptureAssetContextResult,
) -> str:
    extracted = result.extracted_text
    if not extracted:
        return user_text
    return f"{user_text}\n\n以下是用户附加的已提取内容：\n{extracted}"


def _base_context(asset: Asset) -> CaptureAssetContext:
    return CaptureAssetContext(
        asset_id=asset.id,
        kind=asset.kind,
        asset_type=asset.asset_type,
        name=asset.filename or asset.external_url or asset.id,
        mime_type=asset.mime_type,
        size_bytes=asset.size_bytes,
        source_url=asset.external_url,
        status="metadata_only",
        extractor="metadata",
        metadata={
            "sync_status": asset.sync_status,
            "visibility": asset.visibility,
            "storage_provider": asset.storage_provider,
            "external_provider": asset.external_provider,
        },
    )
