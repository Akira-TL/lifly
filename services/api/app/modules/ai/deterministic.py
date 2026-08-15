from __future__ import annotations

from app.modules.ai.contracts import AiPlanRequest, CandidateActionEnvelope
from app.modules.ai.provider import AiProviderOutputError
from app.modules.mcp.parse_engine import parse_mixed_input


class DeterministicRulePlanner:
    """Adapter from the existing deterministic MCP parser to the AI action contract."""

    def plan(self, request: AiPlanRequest) -> CandidateActionEnvelope:
        legacy = parse_mixed_input(
            request.text,
            timezone_str=request.timezone,
            locale=request.locale,
        )
        try:
            return CandidateActionEnvelope.model_validate(
                {
                    "actions": [
                        {
                            "type": action.type,
                            "payload": action.payload,
                            "confidence": action.confidence,
                            "raw_text": action.raw_text or None,
                        }
                        for action in legacy.actions
                    ]
                }
            )
        except (TypeError, ValueError) as exc:
            raise AiProviderOutputError(
                "deterministic parser returned contract-invalid candidate actions"
            ) from exc
