from __future__ import annotations

from collections.abc import Callable

import httpx

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPlanResult,
    AiProviderConfig,
    AiProviderHealth,
    AiTokenUsage,
    ProviderHealthState,
)
from app.modules.ai.provider import AiProvider, AiProviderError
from app.modules.ai.structured_output import parse_candidate_actions, provider_messages

SecretResolver = Callable[[str], str | None]


class OpenAiCompatibleProvider(AiProvider):
    def __init__(
        self,
        config: AiProviderConfig,
        *,
        secret_resolver: SecretResolver | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(config)
        self._secret_resolver = secret_resolver
        self._http_client = http_client

    def _url(self, path: str) -> str:
        return f"{str(self.config.endpoint).rstrip('/')}{path}"

    def _headers(self) -> dict[str, str]:
        reference = self.config.secret_reference
        if reference is None:
            return {}
        if self._secret_resolver is None:
            raise AiProviderError("provider credential resolver unavailable")
        secret = self._secret_resolver(reference)
        if not secret:
            raise AiProviderError("provider credential unavailable")
        return {"Authorization": f"Bearer {secret}"}

    async def _request_client(self):
        if self._http_client is not None:
            return self._http_client, False
        return httpx.AsyncClient(timeout=self.config.timeout_seconds), True

    async def plan(self, request: AiPlanRequest) -> AiPlanResult:
        client, owned = await self._request_client()
        try:
            response = await client.post(
                self._url("/chat/completions"),
                headers=self._headers(),
                json={
                    "model": self.config.model,
                    "messages": provider_messages(request),
                    "response_format": {"type": "json_object"},
                    "temperature": 0,
                },
            )
            response.raise_for_status()
            body = response.json()
            choices = body.get("choices")
            if not isinstance(choices, list) or not choices:
                raise AiProviderError("provider response did not include choices")
            message = choices[0].get("message") if isinstance(choices[0], dict) else None
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, str):
                raise AiProviderError("provider response did not include message content")
            actions = parse_candidate_actions(content)
            usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
            return AiPlanResult(
                provider=self.config.kind,
                model=self.config.model,
                actions=actions.actions,
                usage=AiTokenUsage(
                    input_tokens=int(usage.get("prompt_tokens") or 0),
                    output_tokens=int(usage.get("completion_tokens") or 0),
                ),
            )
        except AiProviderError:
            raise
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            raise AiProviderError("openai-compatible provider unavailable") from exc
        finally:
            if owned:
                await client.aclose()

    async def health(self) -> AiProviderHealth:
        client, owned = await self._request_client()
        try:
            response = await client.get(self._url("/models"), headers=self._headers())
            response.raise_for_status()
            return AiProviderHealth(
                provider=self.config.kind,
                model=self.config.model,
                state=ProviderHealthState.HEALTHY,
            )
        except AiProviderError as exc:
            return AiProviderHealth(
                provider=self.config.kind,
                model=self.config.model,
                state=ProviderHealthState.UNAVAILABLE,
                detail=str(exc),
            )
        except httpx.HTTPError:
            return AiProviderHealth(
                provider=self.config.kind,
                model=self.config.model,
                state=ProviderHealthState.UNAVAILABLE,
                detail="openai-compatible endpoint unavailable",
            )
        finally:
            if owned:
                await client.aclose()
