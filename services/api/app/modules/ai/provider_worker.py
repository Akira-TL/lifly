from __future__ import annotations

import asyncio
import json
import os
import sys
from typing import Any

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPrivacyBoundary,
    AiProviderConfig,
    AiProviderKind,
)
from app.modules.ai.deterministic import DeterministicRulePlanner
from app.modules.ai.engine import AiPlanningEngine
from app.modules.ai.providers.ollama import OllamaAiProvider
from app.modules.ai.providers.openai_compatible import OpenAiCompatibleProvider


def _local_provider_from_environment():
    raw_kind = os.getenv("LIFLY_LOCAL_AI_PROVIDER", AiProviderKind.OLLAMA.value)
    try:
        kind = AiProviderKind(raw_kind)
    except ValueError as exc:
        raise RuntimeError("unsupported local AI provider") from exc

    model = os.getenv("LIFLY_LOCAL_AI_MODEL")
    if not model:
        raise RuntimeError("LIFLY_LOCAL_AI_MODEL is required")

    if kind == AiProviderKind.OLLAMA:
        return OllamaAiProvider(
            AiProviderConfig(
                kind=kind,
                endpoint=os.getenv("LIFLY_LOCAL_AI_ENDPOINT", "http://127.0.0.1:11434"),
                model=model,
                privacy_boundary=AiPrivacyBoundary.LOCAL_DEVICE,
                data_leaves_device=False,
            )
        )

    if kind == AiProviderKind.OPENAI_COMPATIBLE:
        endpoint = os.getenv("LIFLY_LOCAL_AI_ENDPOINT")
        if not endpoint:
            raise RuntimeError("LIFLY_LOCAL_AI_ENDPOINT is required")
        secret_reference = os.getenv("LIFLY_LOCAL_AI_SECRET_REF")
        return OpenAiCompatibleProvider(
            AiProviderConfig(
                kind=kind,
                endpoint=endpoint,
                model=model,
                secret_reference=secret_reference,
                privacy_boundary=AiPrivacyBoundary.USER_ENDPOINT,
                data_leaves_device=True,
            ),
            secret_resolver=lambda reference: os.getenv(reference),
        )

    raise RuntimeError("local AI provider must be ollama or openai_compatible")


async def _plan(payload: dict[str, Any]) -> dict[str, Any]:
    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        raise ValueError("provider worker text must be non-empty")
    request = AiPlanRequest(
        text=text.strip(),
        timezone=str(payload.get("timezone") or "Asia/Shanghai"),
        locale=str(payload.get("locale") or "zh-CN"),
    )
    engine = AiPlanningEngine(fallback=DeterministicRulePlanner())
    result = await engine.plan(_local_provider_from_environment(), request)
    return {
        "schema_version": 1,
        "provider": result.provider.value,
        "model": result.model,
        "fallback_used": result.fallback_used,
        "actions": [
            action.model_dump(mode="json", by_alias=True, exclude_none=True)
            for action in result.actions
        ],
    }


def main() -> None:
    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            raw = json.loads(line)
            if not isinstance(raw, dict):
                raise ValueError("provider worker request must be an object")
            response = asyncio.run(_plan(raw))
            print(json.dumps({"ok": True, "result": response}, ensure_ascii=False), flush=True)
        except Exception:
            # Never echo payload/provider exception text to the caller. The host
            # may choose deterministic Local Core execution when this helper is unavailable.
            print(json.dumps({"ok": False, "error": "local_ai_provider_unavailable"}), flush=True)


if __name__ == "__main__":
    main()
