from __future__ import annotations

import json

from pydantic import ValidationError

from app.modules.ai.contracts import AiPlanRequest, CandidateActionEnvelope
from app.modules.ai.provider import AiProviderOutputError

SYSTEM_INSTRUCTION = """You are Lifly's planning model. Return JSON only.
Produce only structured candidate actions; never claim that an action was committed.
Allowed action types are memo_create, task_create, expense_create, and asset_register_external_url.
Follow the supplied JSON schema exactly. Do not add unknown fields.
"""


def provider_messages(request: AiPlanRequest) -> list[dict[str, str]]:
    context = "\n".join(
        f"[{item.data_type}] {item.content}" for item in request.context
    )
    user_content = (
        f"timezone={request.timezone}\nlocale={request.locale}\n"
        f"input={request.text}"
    )
    if context:
        user_content += f"\ncontext:\n{context}"
    return [
        {"role": "system", "content": SYSTEM_INSTRUCTION},
        {"role": "user", "content": user_content},
    ]


def parse_candidate_actions(content: str) -> CandidateActionEnvelope:
    try:
        payload = json.loads(content)
        return CandidateActionEnvelope.model_validate(payload)
    except (json.JSONDecodeError, ValidationError, TypeError, ValueError) as exc:
        raise AiProviderOutputError(
            "provider returned invalid structured candidate actions"
        ) from exc
