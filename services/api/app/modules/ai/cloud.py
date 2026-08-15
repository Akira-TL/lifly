from __future__ import annotations

import time
from typing import Literal, Protocol

from pydantic import BaseModel, ConfigDict, Field

from app.modules.ai.contracts import (
    AiContextItem,
    AiPlanRequest,
    AiPrivacyBoundary,
    AiProviderKind,
    CandidateAction,
)
from app.modules.ai.provider import AiProvider


class CloudAiConsentError(ValueError):
    """The disclosed plaintext exceeds or lacks explicit user authorization."""


class CloudAiDisclosureScope(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    consent_id: str = Field(min_length=1)
    mode: Literal["once"] = "once"
    granted: bool
    destination: Literal["lifly_cloud_ai"] = "lifly_cloud_ai"
    provider: AiProviderKind
    model: str = Field(min_length=1)
    allowed_data_types: tuple[str, ...] = Field(min_length=1)
    reason: str = Field(min_length=1)
    includes_attachments: bool = False
    includes_history: bool = False


class CloudAiInferenceRequest(BaseModel):
    """Ephemeral plaintext request accepted only after explicit disclosure."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    request_id: str = Field(min_length=1)
    disclosure: CloudAiDisclosureScope
    input: AiContextItem
    context: tuple[AiContextItem, ...] = ()
    history: tuple[AiContextItem, ...] = ()
    attachments: tuple[AiContextItem, ...] = ()
    timezone: str = Field(default="Asia/Shanghai", min_length=1)
    locale: str = Field(default="zh-CN", min_length=1)


class CloudAiInferenceResponse(BaseModel):
    """Candidate-action-only cloud result; never a committed business mutation."""

    model_config = ConfigDict(extra="forbid")

    request_id: str
    provider: AiProviderKind
    model: str
    actions: list[CandidateAction]


class CloudAiOperationalMetadata(BaseModel):
    """The complete allowlist for Cloud AI observability/retention."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    request_id: str
    provider: AiProviderKind
    model: str
    latency_ms: int = Field(ge=0)
    input_tokens: int = Field(default=0, ge=0)
    output_tokens: int = Field(default=0, ge=0)
    status: Literal["success", "error"]


class CloudAiOperationalRecorder(Protocol):
    def record(self, metadata: CloudAiOperationalMetadata) -> None: ...


class _NoopOperationalRecorder:
    def record(self, metadata: CloudAiOperationalMetadata) -> None:
        del metadata


class CloudAiInferenceGateway:
    """Stateless selective-disclosure inference gateway.

    The gateway has no database/session dependency, keeps no request history,
    emits no payload logging, and calls exactly the injected provider. Provider
    errors are propagated; this path never performs an automatic fallback.
    """

    def __init__(
        self,
        provider: AiProvider,
        *,
        recorder: CloudAiOperationalRecorder | None = None,
    ) -> None:
        self._provider = provider
        self._recorder = recorder or _NoopOperationalRecorder()

    def _validate_disclosure(self, request: CloudAiInferenceRequest) -> None:
        disclosure = request.disclosure
        if not disclosure.granted:
            raise CloudAiConsentError("Cloud AI requires explicit consent")
        if self._provider.config.privacy_boundary != AiPrivacyBoundary.CLOUD_DISCLOSURE:
            raise CloudAiConsentError("provider is not configured for cloud disclosure")
        if disclosure.provider != self._provider.config.kind:
            raise CloudAiConsentError("disclosed provider does not match execution provider")
        if disclosure.model != self._provider.config.model:
            raise CloudAiConsentError("disclosed model does not match execution model")
        if request.history and not disclosure.includes_history:
            raise CloudAiConsentError("history was not authorized for disclosure")
        if request.attachments and not disclosure.includes_attachments:
            raise CloudAiConsentError("attachments were not authorized for disclosure")

        allowed = frozenset(disclosure.allowed_data_types)
        disclosed_items = (
            request.input,
            *request.context,
            *request.history,
            *request.attachments,
        )
        for item in disclosed_items:
            if item.data_type not in allowed:
                raise CloudAiConsentError(
                    f"data type {item.data_type!r} is outside disclosure scope"
                )

    async def infer(self, request: CloudAiInferenceRequest) -> CloudAiInferenceResponse:
        self._validate_disclosure(request)
        provider_request = AiPlanRequest(
            text=request.input.content,
            timezone=request.timezone,
            locale=request.locale,
            context=request.context + request.history + request.attachments,
        )
        started = time.perf_counter()
        try:
            result = await self._provider.plan(provider_request)
        except Exception:
            self._recorder.record(
                CloudAiOperationalMetadata(
                    request_id=request.request_id,
                    provider=self._provider.config.kind,
                    model=self._provider.config.model,
                    latency_ms=max(0, int((time.perf_counter() - started) * 1000)),
                    status="error",
                )
            )
            raise

        self._recorder.record(
            CloudAiOperationalMetadata(
                request_id=request.request_id,
                provider=result.provider,
                model=result.model,
                latency_ms=max(0, int((time.perf_counter() - started) * 1000)),
                input_tokens=result.usage.input_tokens,
                output_tokens=result.usage.output_tokens,
                status="success",
            )
        )
        return CloudAiInferenceResponse(
            request_id=request.request_id,
            provider=result.provider,
            model=result.model,
            actions=result.actions,
        )
