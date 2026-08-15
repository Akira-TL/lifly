from __future__ import annotations

import httpx

from app.modules.ai.contracts import (
    AiPlanRequest,
    AiPlanResult,
    AiProviderConfig,
    AiProviderHealth,
    AiTokenUsage,
    CandidateActionEnvelope,
    ProviderHealthState,
)
from app.modules.ai.provider import AiProvider, AiProviderError
from app.modules.ai.structured_output import parse_candidate_actions, provider_messages


class OllamaAiProvider(AiProvider):
    def __init__(
        self,
        config: AiProviderConfig,
        *,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(config)
        self._http_client = http_client

    def _url(self, path: str) -> str:
        return f"{str(self.config.endpoint).rstrip('/')}{path}"

    async def _request_client(self):
        if self._http_client is not None:
            return self._http_client, False
        return httpx.AsyncClient(timeout=self.config.timeout_seconds), True

    async def plan(self, request: AiPlanRequest) -> AiPlanResult:
        client, owned = await self._request_client()
        try:
            response = await client.post(
                self._url("/api/chat"),
                json={
                    "model": self.config.model,
                    "stream": False,
                    "format": CandidateActionEnvelope.model_json_schema(),
                    "messages": provider_messages(request),
                },
            )
            response.raise_for_status()
            body = response.json()
            message = body.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            if not isinstance(content, str):
                raise AiProviderError("provider response did not include message content")
            actions = parse_candidate_actions(content)
            return AiPlanResult(
                provider=self.config.kind,
                model=self.config.model,
                actions=actions.actions,
                usage=AiTokenUsage(
                    input_tokens=int(body.get("prompt_eval_count") or 0),
                    output_tokens=int(body.get("eval_count") or 0),
                ),
            )
        except AiProviderError:
            raise
        except (httpx.HTTPError, ValueError, TypeError) as exc:
            raise AiProviderError("ollama provider unavailable") from exc
        finally:
            if owned:
                await client.aclose()

    async def health(self) -> AiProviderHealth:
        client, owned = await self._request_client()
        try:
            response = await client.get(self._url("/api/tags"))
            response.raise_for_status()
            return AiProviderHealth(
                provider=self.config.kind,
                model=self.config.model,
                state=ProviderHealthState.HEALTHY,
            )
        except httpx.HTTPError:
            return AiProviderHealth(
                provider=self.config.kind,
                model=self.config.model,
                state=ProviderHealthState.UNAVAILABLE,
                detail="ollama endpoint unavailable",
            )
        finally:
            if owned:
                await client.aclose()
