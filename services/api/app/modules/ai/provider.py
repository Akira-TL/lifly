from __future__ import annotations

from abc import ABC, abstractmethod

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPlanResult,
    AiProviderCapabilities,
    AiProviderConfig,
    AiProviderHealth,
)


class AiProviderError(RuntimeError):
    """Sanitized provider failure safe to surface without payload content."""


class AiProviderOutputError(AiProviderError):
    """Provider returned malformed or contract-invalid structured output."""


class AiProvider(ABC):
    """Small seam shared by local, user-hosted, and cloud-backed providers."""

    def __init__(self, config: AiProviderConfig) -> None:
        self._config = config

    @property
    def config(self) -> AiProviderConfig:
        return self._config

    async def capabilities(self) -> AiProviderCapabilities:
        return AiProviderCapabilities()

    @abstractmethod
    async def plan(self, request: AiPlanRequest) -> AiPlanResult:
        raise NotImplementedError

    @abstractmethod
    async def health(self) -> AiProviderHealth:
        raise NotImplementedError
