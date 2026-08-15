from __future__ import annotations

import asyncio
from collections.abc import Mapping

import httpx
import pytest
from pydantic import ValidationError

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPrivacyBoundary,
    AiProviderConfig,
    AiProviderKind,
    CandidateActionEnvelope,
)
from app.modules.ai.deterministic import DeterministicRulePlanner
from app.modules.ai.engine import AiPlanningEngine
from app.modules.ai.provider import AiProvider, AiProviderError
from app.modules.ai.providers.ollama import OllamaAiProvider
from app.modules.ai.providers.openai_compatible import OpenAiCompatibleProvider


def _request() -> AiPlanRequest:
    return AiPlanRequest(text="明天上午十点提醒我交报告", timezone="Asia/Shanghai", locale="zh-CN")


def _ollama_config() -> AiProviderConfig:
    return AiProviderConfig(
        kind=AiProviderKind.OLLAMA,
        endpoint="http://ollama.local:11434",
        model="test-model",
        privacy_boundary=AiPrivacyBoundary.LOCAL_DEVICE,
        data_leaves_device=False,
    )


def test_candidate_actions_are_strictly_validated() -> None:
    valid = CandidateActionEnvelope.model_validate(
        {
            "actions": [
                {
                    "type": "task_create",
                    "payload": {
                        "title": "交报告",
                        "remind_at": "2026-08-16T10:00:00+08:00",
                        "priority": "normal",
                    },
                    "confidence": 0.91,
                }
            ]
        }
    )
    assert valid.actions[0].type == "task_create"

    with pytest.raises(ValidationError):
        CandidateActionEnvelope.model_validate(
            {
                "actions": [
                    {
                        "type": "expense_create",
                        "payload": {
                            "currency": "CNY",
                            "direction": "expense",
                            "merchant": "食堂",
                            "occurred_at": "2026-08-15T12:00:00+08:00",
                        },
                        "confidence": 0.9,
                    }
                ]
            }
        )

    with pytest.raises(ValidationError):
        CandidateActionEnvelope.model_validate(
            {
                "actions": [
                    {
                        "type": "task_create",
                        "payload": {
                            "title": "交报告",
                            "remind_at": "2026-08-16T10:00:00+08:00",
                            "priority": "normal",
                            "unexpected": "must fail closed",
                        },
                        "confidence": 0.9,
                    }
                ]
            }
        )


def test_ollama_provider_requests_structured_output_and_parses_actions() -> None:
    captured: dict[str, object] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["body"] = request.content.decode()
        return httpx.Response(
            200,
            json={
                "message": {
                    "content": '{"actions":[{"type":"memo_create","payload":{"type":"memo","content_markdown":"hello"},"confidence":0.8}]}'
                },
                "prompt_eval_count": 12,
                "eval_count": 7,
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = OllamaAiProvider(_ollama_config(), http_client=client)
    try:
        result = asyncio.run(provider.plan(_request()))
    finally:
        asyncio.run(client.aclose())

    assert captured["url"] == "http://ollama.local:11434/api/chat"
    assert '"format"' in str(captured["body"])
    assert result.actions[0].type == "memo_create"
    assert result.usage.input_tokens == 12
    assert result.usage.output_tokens == 7


def test_openai_compatible_provider_resolves_secret_reference_at_request_time() -> None:
    captured_headers: Mapping[str, str] | None = None
    resolved: list[str] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal captured_headers
        captured_headers = request.headers
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": '{"actions":[{"type":"task_create","payload":{"title":"交报告","remind_at":"2026-08-16T10:00:00+08:00","priority":"normal"},"confidence":0.95}]}'
                        }
                    }
                ],
                "usage": {"prompt_tokens": 20, "completion_tokens": 8},
            },
        )

    def resolve(reference: str) -> str | None:
        resolved.append(reference)
        return "runtime-secret"

    config = AiProviderConfig(
        kind=AiProviderKind.OPENAI_COMPATIBLE,
        endpoint="https://example.invalid/v1",
        model="compatible-model",
        secret_reference="OPENAI_TEST_KEY",
        privacy_boundary=AiPrivacyBoundary.USER_ENDPOINT,
        data_leaves_device=True,
    )
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    provider = OpenAiCompatibleProvider(config, secret_resolver=resolve, http_client=client)
    try:
        result = asyncio.run(provider.plan(_request()))
    finally:
        asyncio.run(client.aclose())

    assert resolved == ["OPENAI_TEST_KEY"]
    assert captured_headers is not None
    assert captured_headers["authorization"] == "Bearer runtime-secret"
    assert result.actions[0].type == "task_create"


class _FailingProvider(AiProvider):
    def __init__(self, config: AiProviderConfig) -> None:
        super().__init__(config)

    async def plan(self, request: AiPlanRequest):
        raise AiProviderError("provider unavailable")

    async def health(self):
        raise NotImplementedError


class _FallbackPlanner:
    def __init__(self) -> None:
        self.calls = 0

    def plan(self, request: AiPlanRequest) -> CandidateActionEnvelope:
        self.calls += 1
        return CandidateActionEnvelope.model_validate(
            {
                "actions": [
                    {
                        "type": "memo_create",
                        "payload": {"type": "memo", "content_markdown": request.text},
                        "confidence": 0.4,
                    }
                ]
            }
        )


def test_existing_rule_parser_is_available_as_strict_deterministic_fallback() -> None:
    envelope = DeterministicRulePlanner().plan(
        AiPlanRequest(text="在食堂花了18元", timezone="Asia/Shanghai", locale="zh-CN")
    )

    expense = next(action for action in envelope.actions if action.type == "expense_create")
    assert expense.payload.amount == 18
    assert expense.payload.currency == "CNY"


def test_local_provider_failure_uses_deterministic_fallback() -> None:
    fallback = _FallbackPlanner()
    engine = AiPlanningEngine(fallback=fallback)
    result = asyncio.run(engine.plan(_FailingProvider(_ollama_config()), _request()))

    assert result.fallback_used is True
    assert result.actions[0].type == "memo_create"
    assert fallback.calls == 1


def test_cloud_privacy_boundary_never_uses_automatic_fallback() -> None:
    fallback = _FallbackPlanner()
    config = AiProviderConfig(
        kind=AiProviderKind.LIFLY_CLOUD,
        endpoint="https://cloud.invalid/ai",
        model="cloud-model",
        privacy_boundary=AiPrivacyBoundary.CLOUD_DISCLOSURE,
        data_leaves_device=True,
    )
    engine = AiPlanningEngine(fallback=fallback)

    with pytest.raises(AiProviderError, match="provider unavailable"):
        asyncio.run(engine.plan(_FailingProvider(config), _request()))

    assert fallback.calls == 0
