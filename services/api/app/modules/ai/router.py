from __future__ import annotations

import os

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import AuthenticatedSubject, get_authenticated_subject
from app.modules.ai.cloud import (
    CloudAiConsentError,
    CloudAiInferenceGateway,
    CloudAiInferenceRequest,
    CloudAiInferenceResponse,
)
from app.modules.ai.contracts import (
    AiPrivacyBoundary,
    AiProviderConfig,
    AiProviderKind,
)
from app.modules.ai.provider import AiProviderError
from app.modules.ai.providers.ollama import OllamaAiProvider
from app.modules.ai.providers.openai_compatible import OpenAiCompatibleProvider

router = APIRouter()


def _cloud_provider_from_environment():
    raw_kind = os.getenv("LIFLY_CLOUD_AI_PROVIDER", AiProviderKind.OLLAMA.value)
    try:
        kind = AiProviderKind(raw_kind)
    except ValueError as exc:
        raise RuntimeError("unsupported Lifly Cloud AI provider") from exc

    model = os.getenv("LIFLY_CLOUD_AI_MODEL")
    if not model:
        raise RuntimeError("LIFLY_CLOUD_AI_MODEL is required")

    if kind == AiProviderKind.OLLAMA:
        endpoint = os.getenv("LIFLY_CLOUD_AI_ENDPOINT", "http://127.0.0.1:11434")
        config = AiProviderConfig(
            kind=kind,
            endpoint=endpoint,
            model=model,
            privacy_boundary=AiPrivacyBoundary.CLOUD_DISCLOSURE,
            data_leaves_device=True,
        )
        return OllamaAiProvider(config)

    if kind == AiProviderKind.OPENAI_COMPATIBLE:
        endpoint = os.getenv("LIFLY_CLOUD_AI_ENDPOINT")
        if not endpoint:
            raise RuntimeError("LIFLY_CLOUD_AI_ENDPOINT is required")
        secret_reference = os.getenv("LIFLY_CLOUD_AI_SECRET_REF")
        config = AiProviderConfig(
            kind=kind,
            endpoint=endpoint,
            model=model,
            secret_reference=secret_reference,
            privacy_boundary=AiPrivacyBoundary.CLOUD_DISCLOSURE,
            data_leaves_device=True,
        )
        return OpenAiCompatibleProvider(
            config,
            secret_resolver=lambda reference: os.getenv(reference),
        )

    raise RuntimeError("Lifly Cloud AI supports ollama or openai_compatible only")


def get_cloud_ai_gateway() -> CloudAiInferenceGateway:
    try:
        return CloudAiInferenceGateway(_cloud_provider_from_environment())
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/cloud/plan", response_model=CloudAiInferenceResponse)
async def cloud_plan(
    request: CloudAiInferenceRequest,
    subject: AuthenticatedSubject = Depends(get_authenticated_subject),
    gateway: CloudAiInferenceGateway = Depends(get_cloud_ai_gateway),
) -> CloudAiInferenceResponse:
    # Authentication gates the cloud entry point. Account identity is not added
    # to the model prompt or retained by the stateless inference gateway.
    del subject
    try:
        return await gateway.infer(request)
    except CloudAiConsentError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except AiProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
