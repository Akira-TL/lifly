from __future__ import annotations

from enum import StrEnum
from typing import Annotated, Literal

from pydantic import AwareDatetime, AnyHttpUrl, BaseModel, ConfigDict, Field

AI_PROVIDER_CONTRACT_VERSION = 1


class AiProviderKind(StrEnum):
    DETERMINISTIC = "deterministic"
    OLLAMA = "ollama"
    OPENAI_COMPATIBLE = "openai_compatible"
    LIFLY_CLOUD = "lifly_cloud"


class AiPrivacyBoundary(StrEnum):
    LOCAL_DEVICE = "local_device"
    USER_ENDPOINT = "user_endpoint"
    CLOUD_DISCLOSURE = "cloud_disclosure"


class ProviderHealthState(StrEnum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNAVAILABLE = "unavailable"


class AiContextItem(BaseModel):
    """Transient context supplied to a provider for one inference."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    data_type: str = Field(min_length=1, max_length=64)
    content: str = Field(min_length=1)


class AiPlanRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    text: str = Field(min_length=1)
    timezone: str = Field(default="Asia/Shanghai", min_length=1)
    locale: str = Field(default="zh-CN", min_length=1)
    context: tuple[AiContextItem, ...] = ()


class MemoCreatePayload(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    memo_type: Literal["memo", "journal"] = Field(default="memo", alias="type")
    content_markdown: str = Field(min_length=1)
    mood: str | None = None


class TaskCreatePayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1)
    remind_at: AwareDatetime | None = None
    priority: Literal["low", "normal", "high", "urgent"] = "normal"


class ExpenseCreatePayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    amount: float = Field(gt=0)
    currency: str = Field(default="CNY", min_length=3, max_length=3)
    direction: Literal["expense", "income"] = "expense"
    merchant: str = Field(default="未知商户", min_length=1)
    category_hint: str | None = None
    occurred_at: AwareDatetime


class AssetRegisterExternalUrlPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    external_url: AnyHttpUrl
    title: str | None = None


class _CandidateActionBase(BaseModel):
    model_config = ConfigDict(extra="forbid")

    confidence: float = Field(ge=0, le=1)
    raw_text: str | None = None


class MemoCreateAction(_CandidateActionBase):
    type: Literal["memo_create"]
    payload: MemoCreatePayload


class TaskCreateAction(_CandidateActionBase):
    type: Literal["task_create"]
    payload: TaskCreatePayload


class ExpenseCreateAction(_CandidateActionBase):
    type: Literal["expense_create"]
    payload: ExpenseCreatePayload


class AssetRegisterExternalUrlAction(_CandidateActionBase):
    type: Literal["asset_register_external_url"]
    payload: AssetRegisterExternalUrlPayload


CandidateAction = Annotated[
    MemoCreateAction
    | TaskCreateAction
    | ExpenseCreateAction
    | AssetRegisterExternalUrlAction,
    Field(discriminator="type"),
]


class CandidateActionEnvelope(BaseModel):
    """Strict provider output. Unknown actions/fields fail closed."""

    model_config = ConfigDict(extra="forbid")

    actions: list[CandidateAction] = Field(default_factory=list, max_length=16)


class AiTokenUsage(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    input_tokens: int = Field(default=0, ge=0)
    output_tokens: int = Field(default=0, ge=0)


class AiPlanResult(BaseModel):
    model_config = ConfigDict(extra="forbid")

    provider: AiProviderKind
    model: str
    actions: list[CandidateAction]
    usage: AiTokenUsage = Field(default_factory=AiTokenUsage)
    fallback_used: bool = False


class AiProviderCapabilities(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    structured_candidate_actions: Literal[True] = True
    action_types: tuple[str, ...] = (
        "memo_create",
        "task_create",
        "expense_create",
        "asset_register_external_url",
    )


class AiProviderHealth(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    provider: AiProviderKind
    model: str
    state: ProviderHealthState
    detail: str | None = None


class AiProviderConfig(BaseModel):
    """Non-secret Provider configuration.

    ``secret_reference`` names a Secure Secret Store/environment entry. The
    credential value itself is intentionally not part of this contract.
    """

    model_config = ConfigDict(extra="forbid", frozen=True)

    kind: AiProviderKind
    endpoint: AnyHttpUrl
    model: str = Field(min_length=1)
    secret_reference: str | None = None
    privacy_boundary: AiPrivacyBoundary
    data_leaves_device: bool
    timeout_seconds: float = Field(default=30.0, gt=0, le=300)
