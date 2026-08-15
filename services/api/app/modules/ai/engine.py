from __future__ import annotations

from typing import Protocol

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPlanResult,
    AiPrivacyBoundary,
    AiProviderKind,
    CandidateActionEnvelope,
)
from app.modules.ai.provider import AiProvider, AiProviderError


class DeterministicFallback(Protocol):
    def plan(self, request: AiPlanRequest) -> CandidateActionEnvelope: ...


class AiPlanningEngine:
    """Provider orchestration with a deterministic local safety fallback.

    The Cloud AI privacy boundary deliberately bypasses automatic fallback.
    A caller must explicitly select/authorize another execution path instead.
    """

    def __init__(self, *, fallback: DeterministicFallback) -> None:
        self._fallback = fallback

    async def plan(self, provider: AiProvider, request: AiPlanRequest) -> AiPlanResult:
        try:
            return await provider.plan(request)
        except AiProviderError:
            if provider.config.privacy_boundary == AiPrivacyBoundary.CLOUD_DISCLOSURE:
                raise

        fallback_result = self._fallback.plan(request)
        return AiPlanResult(
            provider=AiProviderKind.DETERMINISTIC,
            model="deterministic-rules",
            actions=fallback_result.actions,
            fallback_used=True,
        )
