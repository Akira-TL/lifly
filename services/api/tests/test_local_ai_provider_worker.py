from __future__ import annotations

import asyncio

from app.modules.ai import provider_worker
from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPlanResult,
    AiPrivacyBoundary,
    AiProviderConfig,
    AiProviderHealth,
    AiProviderKind,
    CandidateActionEnvelope,
    ProviderHealthState,
)
from app.modules.ai.provider import AiProvider, AiProviderError


class _Provider(AiProvider):
    def __init__(self, *, fails: bool = False) -> None:
        super().__init__(
            AiProviderConfig(
                kind=AiProviderKind.OLLAMA,
                endpoint="http://127.0.0.1:8205",
                model="local-demo",
                privacy_boundary=AiPrivacyBoundary.LOCAL_DEVICE,
                data_leaves_device=False,
            )
        )
        self._fails = fails

    async def plan(self, request: AiPlanRequest) -> AiPlanResult:
        if self._fails:
            raise AiProviderError("sanitized local failure")
        actions = CandidateActionEnvelope.model_validate(
            {
                "actions": [
                    {
                        "type": "memo_create",
                        "payload": {
                            "type": "memo",
                            "content_markdown": request.text,
                        },
                        "confidence": 0.93,
                    }
                ]
            }
        )
        return AiPlanResult(
            provider=AiProviderKind.OLLAMA,
            model="local-demo",
            actions=actions.actions,
        )

    async def health(self) -> AiProviderHealth:
        return AiProviderHealth(
            provider=AiProviderKind.OLLAMA,
            model="local-demo",
            state=ProviderHealthState.HEALTHY,
        )


def test_local_provider_worker_returns_agent3_structured_candidates(monkeypatch) -> None:
    monkeypatch.setattr(provider_worker, "_local_provider_from_environment", lambda: _Provider())

    result = asyncio.run(provider_worker._plan({"text": "本机 Ollama 候选动作"}))

    assert result["provider"] == "ollama"
    assert result["model"] == "local-demo"
    assert result["fallback_used"] is False
    assert result["actions"][0]["type"] == "memo_create"
    assert result["actions"][0]["payload"]["content_markdown"] == "本机 Ollama 候选动作"


def test_local_provider_failure_uses_only_deterministic_local_fallback(monkeypatch) -> None:
    monkeypatch.setattr(
        provider_worker,
        "_local_provider_from_environment",
        lambda: _Provider(fails=True),
    )

    result = asyncio.run(provider_worker._plan({"text": "本机 provider 失败后仍留在设备"}))

    assert result["provider"] == "deterministic"
    assert result["fallback_used"] is True
    assert result["actions"]
