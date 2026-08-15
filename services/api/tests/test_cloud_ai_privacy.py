from __future__ import annotations

import asyncio

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.security import AuthenticatedSubject, get_authenticated_subject
from app.modules.ai.cloud import (
    CloudAiConsentError,
    CloudAiDisclosureScope,
    CloudAiInferenceGateway,
    CloudAiInferenceRequest,
    CloudAiOperationalMetadata,
    CloudAiOperationalRecorder,
)
from app.modules.ai.contracts import (
    AiContextItem,
    AiPlanRequest,
    AiPlanResult,
    AiPrivacyBoundary,
    AiProviderConfig,
    AiProviderKind,
    CandidateActionEnvelope,
)
from app.modules.ai.provider import AiProvider, AiProviderError
from app.modules.ai.router import (
    _cloud_provider_from_environment,
    get_cloud_ai_gateway,
    router as ai_router,
)


class _RecordingProvider(AiProvider):
    def __init__(
        self,
        *,
        fail: bool = False,
        failure_message: str = "provider unavailable",
    ) -> None:
        super().__init__(
            AiProviderConfig(
                kind=AiProviderKind.OLLAMA,
                endpoint="http://cloud-ollama.internal:11434",
                model="cloud-model",
                privacy_boundary=AiPrivacyBoundary.CLOUD_DISCLOSURE,
                data_leaves_device=True,
            )
        )
        self.requests: list[AiPlanRequest] = []
        self.fail = fail
        self.failure_message = failure_message

    async def plan(self, request: AiPlanRequest) -> AiPlanResult:
        self.requests.append(request)
        if self.fail:
            raise AiProviderError(self.failure_message)
        actions = CandidateActionEnvelope.model_validate(
            {
                "actions": [
                    {
                        "type": "memo_create",
                        "payload": {
                            "type": "memo",
                            "content_markdown": "候选结果",
                        },
                        "confidence": 0.88,
                    }
                ]
            }
        )
        return AiPlanResult(
            provider=self.config.kind,
            model=self.config.model,
            actions=actions.actions,
        )

    async def health(self):
        raise NotImplementedError


class _Recorder(CloudAiOperationalRecorder):
    def __init__(self) -> None:
        self.items: list[CloudAiOperationalMetadata] = []

    def record(self, metadata: CloudAiOperationalMetadata) -> None:
        self.items.append(metadata)


def _request(*, granted: bool = True) -> CloudAiInferenceRequest:
    return CloudAiInferenceRequest(
        request_id="req-1",
        disclosure=CloudAiDisclosureScope(
            consent_id="consent-1",
            mode="once",
            granted=granted,
            destination="lifly_cloud_ai",
            provider=AiProviderKind.OLLAMA,
            model="cloud-model",
            allowed_data_types=("user_input", "memo_excerpt"),
            reason="根据当前输入生成候选动作",
            includes_attachments=False,
            includes_history=False,
        ),
        input=AiContextItem(data_type="user_input", content="这是秘密输入"),
        context=(AiContextItem(data_type="memo_excerpt", content="这是最小上下文"),),
    )


def test_cloud_ai_requires_explicit_once_consent_before_provider_call() -> None:
    provider = _RecordingProvider()
    gateway = CloudAiInferenceGateway(provider)

    with pytest.raises(CloudAiConsentError, match="explicit consent"):
        asyncio.run(gateway.infer(_request(granted=False)))

    assert provider.requests == []


def test_cloud_ai_rejects_context_outside_disclosure_scope() -> None:
    provider = _RecordingProvider()
    gateway = CloudAiInferenceGateway(provider)
    request = _request().model_copy(
        update={
            "context": (
                AiContextItem(data_type="ledger_history", content="不在授权范围"),
            )
        }
    )

    with pytest.raises(CloudAiConsentError, match="outside disclosure scope"):
        asyncio.run(gateway.infer(request))

    assert provider.requests == []


def test_cloud_ai_passes_only_disclosed_plaintext_and_records_metadata_only() -> None:
    provider = _RecordingProvider()
    recorder = _Recorder()
    gateway = CloudAiInferenceGateway(provider, recorder=recorder)

    response = asyncio.run(gateway.infer(_request()))

    assert len(provider.requests) == 1
    provider_request = provider.requests[0]
    assert provider_request.text == "这是秘密输入"
    assert [item.content for item in provider_request.context] == ["这是最小上下文"]
    assert response.actions[0].type == "memo_create"

    assert len(recorder.items) == 1
    metadata = recorder.items[0]
    dumped = metadata.model_dump_json()
    assert metadata.status == "success"
    assert "这是秘密输入" not in dumped
    assert "这是最小上下文" not in dumped
    assert "候选结果" not in dumped
    assert set(type(metadata).model_fields) == {
        "request_id",
        "provider",
        "model",
        "latency_ms",
        "input_tokens",
        "output_tokens",
        "status",
    }


def test_cloud_ai_rejects_attachments_or_history_not_explicitly_authorized() -> None:
    provider = _RecordingProvider()
    gateway = CloudAiInferenceGateway(provider)
    request = _request().model_copy(
        update={
            "history": (
                AiContextItem(data_type="memo_excerpt", content="history"),
            )
        }
    )

    with pytest.raises(CloudAiConsentError, match="history was not authorized"):
        asyncio.run(gateway.infer(request))

    assert provider.requests == []


def test_cloud_provider_environment_config_keeps_secret_value_out_of_contract(monkeypatch) -> None:
    monkeypatch.setenv("LIFLY_CLOUD_AI_PROVIDER", "openai_compatible")
    monkeypatch.setenv("LIFLY_CLOUD_AI_ENDPOINT", "https://provider.invalid/v1")
    monkeypatch.setenv("LIFLY_CLOUD_AI_MODEL", "cloud-model")
    monkeypatch.setenv("LIFLY_CLOUD_AI_SECRET_REF", "LIFLY_CLOUD_AI_RUNTIME_KEY")
    monkeypatch.setenv("LIFLY_CLOUD_AI_RUNTIME_KEY", "plaintext-secret-value")

    provider = _cloud_provider_from_environment()
    serialized = provider.config.model_dump_json()

    assert provider.config.secret_reference == "LIFLY_CLOUD_AI_RUNTIME_KEY"
    assert "plaintext-secret-value" not in serialized
    assert provider.config.privacy_boundary == AiPrivacyBoundary.CLOUD_DISCLOSURE


def test_cloud_ai_route_is_authenticated_and_returns_candidate_actions_only() -> None:
    provider = _RecordingProvider()
    gateway = CloudAiInferenceGateway(provider)
    app = FastAPI()
    app.include_router(ai_router, prefix="/ai")
    app.dependency_overrides[get_authenticated_subject] = lambda: AuthenticatedSubject(
        account_id="account-1"
    )
    app.dependency_overrides[get_cloud_ai_gateway] = lambda: gateway

    response = TestClient(app).post(
        "/ai/cloud/plan",
        json=_request().model_dump(mode="json"),
    )

    assert response.status_code == 200
    body = response.json()
    assert set(body) == {"request_id", "provider", "model", "actions"}
    assert body["actions"][0]["type"] == "memo_create"
    assert "account-1" not in response.text


def test_cloud_ai_route_does_not_echo_provider_error_payload() -> None:
    provider = _RecordingProvider(fail=True, failure_message="secret-prompt-marker")
    gateway = CloudAiInferenceGateway(provider)
    app = FastAPI()
    app.include_router(ai_router, prefix="/ai")
    app.dependency_overrides[get_authenticated_subject] = lambda: AuthenticatedSubject(
        account_id="account-1"
    )
    app.dependency_overrides[get_cloud_ai_gateway] = lambda: gateway

    response = TestClient(app).post(
        "/ai/cloud/plan",
        json=_request().model_dump(mode="json"),
    )

    assert response.status_code == 503
    assert response.json() == {"detail": "Cloud AI provider unavailable"}
    assert "secret-prompt-marker" not in response.text


def test_cloud_ai_provider_failure_does_not_fallback_or_retain_payload() -> None:
    provider = _RecordingProvider(fail=True)
    recorder = _Recorder()
    gateway = CloudAiInferenceGateway(provider, recorder=recorder)

    with pytest.raises(AiProviderError, match="provider unavailable"):
        asyncio.run(gateway.infer(_request()))

    assert len(provider.requests) == 1
    assert len(recorder.items) == 1
    dumped = recorder.items[0].model_dump_json()
    assert recorder.items[0].status == "error"
    assert "这是秘密输入" not in dumped
    assert "这是最小上下文" not in dumped
