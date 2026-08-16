from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.security import AuthenticatedSubject
from app.modules.ai_relay.contracts import AiJobEnvelope
from app.modules.ai_relay.repository import AiRelayStore, get_ai_relay_store
from app.modules.ai_relay.router import router as ai_relay_router
from app.modules.auth.sessions import get_active_subject
from app.modules.devices.contracts import (
    DeviceCapability,
    DeviceCapabilityReport,
    DeviceTrustState,
)
from app.modules.devices.repository import DeviceNotFound, DeviceRecord, get_device_repository


@dataclass
class _Stored:
    envelope: AiJobEnvelope
    delivery_status: str = "queued"


class _MemoryRelayStore(AiRelayStore):
    def __init__(self) -> None:
        self.items: dict[str, _Stored] = {}

    async def submit_request(self, envelope: AiJobEnvelope) -> AiJobEnvelope:
        existing = self.items.get(envelope.job_id)
        if existing is not None:
            if existing.envelope != envelope:
                raise ValueError("AI relay job id conflict")
            return existing.envelope
        for item in self.items.values():
            other = item.envelope
            if (
                other.account_id == envelope.account_id
                and other.source_device_id == envelope.source_device_id
                and other.idempotency_key == envelope.idempotency_key
                and other.message_type.value == "request"
            ):
                if other != envelope:
                    raise ValueError("AI relay idempotency conflict")
                return other
        self.items[envelope.job_id] = _Stored(envelope)
        return envelope

    async def next_for_target(
        self, *, account_id: str, target_device_id: str, now: datetime
    ) -> AiJobEnvelope | None:
        for item in self.items.values():
            envelope = item.envelope
            if (
                envelope.account_id == account_id
                and envelope.target_device_id == target_device_id
                and envelope.message_type.value == "request"
                and item.delivery_status in {"queued", "delivered"}
            ):
                if envelope.expires_at <= now:
                    item.delivery_status = "expired"
                    continue
                item.delivery_status = "delivered"
                return envelope
        return None

    async def get_request(self, *, account_id: str, job_id: str) -> AiJobEnvelope | None:
        item = self.items.get(job_id)
        if item is None or item.envelope.account_id != account_id:
            return None
        if item.envelope.message_type.value != "request":
            return None
        return item.envelope

    async def delivery_status(self, *, account_id: str, job_id: str) -> str | None:
        item = self.items.get(job_id)
        if item is None or item.envelope.account_id != account_id:
            return None
        return item.delivery_status

    async def mark_failed(self, *, account_id: str, job_id: str) -> None:
        item = self.items.get(job_id)
        if item is None or item.envelope.account_id != account_id:
            raise ValueError("AI relay request not found")
        item.delivery_status = "failed"

    async def submit_result(
        self, *, request: AiJobEnvelope, result: AiJobEnvelope
    ) -> AiJobEnvelope:
        self.items[result.job_id] = _Stored(result)
        self.items[request.job_id].delivery_status = "completed"
        return result

    async def result_for_request(
        self,
        *,
        account_id: str,
        request_job_id: str,
        requester_device_id: str,
        now: datetime,
    ) -> AiJobEnvelope | None:
        for item in self.items.values():
            envelope = item.envelope
            if (
                envelope.account_id == account_id
                and envelope.message_type.value == "result"
                and envelope.correlation_id == request_job_id
                and envelope.target_device_id == requester_device_id
            ):
                if envelope.expires_at <= now:
                    item.delivery_status = "expired"
                    return None
                item.delivery_status = "delivered"
                return envelope
        return None


class _Devices:
    def __init__(self) -> None:
        self.records = {
            "phone-1": _device("phone-1", capabilities=[]),
            "desktop-1": _device(
                "desktop-1", capabilities=[DeviceCapability.LOCAL_AI, DeviceCapability.LOCAL_MCP]
            ),
        }

    async def get_for_account(self, account_id: str, device_id: str) -> DeviceRecord:
        record = self.records.get(device_id)
        if record is None or record.account_id != account_id:
            raise DeviceNotFound(device_id)
        return record


def _device(
    device_id: str,
    *,
    capabilities: list[DeviceCapability],
    trust_state: DeviceTrustState = DeviceTrustState.TRUSTED,
) -> DeviceRecord:
    return DeviceRecord(
        device_id=device_id,
        account_id="account-1",
        display_name=device_id,
        platform="android" if device_id.startswith("phone") else "linux",
        public_key=f"{device_id}-public-key",
        trust_state=trust_state,
        capability_report=DeviceCapabilityReport(capabilities=capabilities),
        is_default_compute_node=device_id == "desktop-1",
        last_seen_at=datetime.now(timezone.utc),
        revoked_at=(datetime.now(timezone.utc) if trust_state == DeviceTrustState.REVOKED else None),
        key_version=1,
        protocol_version=1,
    )


def _request_envelope() -> dict[str, object]:
    return {
        "protocol_version": 1,
        "job_id": "job-request-1",
        "account_id": "account-1",
        "source_device_id": "phone-1",
        "target_device_id": "desktop-1",
        "message_type": "request",
        "correlation_id": None,
        "idempotency_key": "capture-1",
        "expires_at": (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat(),
        "encryption_version": 1,
        "nonce": "opaque-request-nonce",
        "ciphertext": "opaque-request-ciphertext",
    }


def _result_envelope(*, expires_at: str | None = None) -> dict[str, object]:
    return {
        "protocol_version": 1,
        "job_id": "job-result-1",
        "account_id": "account-1",
        "source_device_id": "desktop-1",
        "target_device_id": "phone-1",
        "message_type": "result",
        "correlation_id": "job-request-1",
        "idempotency_key": "capture-1",
        "expires_at": expires_at or (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat(),
        "encryption_version": 1,
        "nonce": "opaque-result-nonce",
        "ciphertext": "opaque-result-ciphertext",
    }


def _client(subject_device_id: str) -> tuple[TestClient, _MemoryRelayStore, _Devices, FastAPI]:
    app = FastAPI()
    app.include_router(ai_relay_router, prefix="/ai/relay")
    store = _MemoryRelayStore()
    devices = _Devices()
    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id=subject_device_id
    )
    app.dependency_overrides[get_ai_relay_store] = lambda: store
    app.dependency_overrides[get_device_repository] = lambda: devices
    return TestClient(app), store, devices, app


def test_authenticated_encrypted_relay_round_trip() -> None:
    phone, store, devices, app = _client("phone-1")

    submitted = phone.post("/ai/relay/jobs", json=_request_envelope())
    assert submitted.status_code == 200
    assert submitted.json()["ciphertext"] == "opaque-request-ciphertext"

    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id="desktop-1"
    )
    desktop = TestClient(app)
    delivered = desktop.get("/ai/relay/jobs/next")
    assert delivered.status_code == 200
    assert delivered.json()["job_id"] == "job-request-1"
    assert delivered.json()["ciphertext"] == "opaque-request-ciphertext"

    result = desktop.post(
        "/ai/relay/results",
        json=_result_envelope(expires_at=submitted.json()["expires_at"]),
    )
    assert result.status_code == 200
    assert result.json()["ciphertext"] == "opaque-result-ciphertext"

    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id="phone-1"
    )
    requester = TestClient(app)
    fetched = requester.get("/ai/relay/jobs/job-request-1/result")
    assert fetched.status_code == 200
    assert fetched.json()["job_id"] == "job-result-1"
    assert fetched.json()["ciphertext"] == "opaque-result-ciphertext"

    assert set(store.items) == {"job-request-1", "job-result-1"}
    assert devices.records["desktop-1"].public_key == "desktop-1-public-key"


def test_terminal_target_failure_stops_redelivery_and_surfaces_to_requester() -> None:
    phone, store, _, app = _client("phone-1")
    assert phone.post("/ai/relay/jobs", json=_request_envelope()).status_code == 200

    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id="desktop-1"
    )
    desktop = TestClient(app)
    delivered = desktop.get("/ai/relay/jobs/next")
    assert delivered.status_code == 200
    assert delivered.json()["job_id"] == "job-request-1"

    failed = desktop.post("/ai/relay/jobs/job-request-1/fail")
    assert failed.status_code == 204
    assert store.items["job-request-1"].delivery_status == "failed"
    assert desktop.get("/ai/relay/jobs/next").json() is None

    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id="phone-1"
    )
    requester = TestClient(app)
    result = requester.get("/ai/relay/jobs/job-request-1/result")
    assert result.status_code == 409
    assert result.json()["detail"] == "AI relay request failed on target device"


def test_relay_rejects_spoofed_account_or_source_device() -> None:
    client, _, _, _ = _client("phone-1")

    spoofed_account = _request_envelope() | {"account_id": "account-2"}
    response = client.post("/ai/relay/jobs", json=spoofed_account)
    assert response.status_code == 403

    spoofed_source = _request_envelope() | {"source_device_id": "phone-2"}
    response = client.post("/ai/relay/jobs", json=spoofed_source)
    assert response.status_code == 403


def test_relay_rejects_revoked_or_non_compute_target() -> None:
    client, _, devices, _ = _client("phone-1")
    devices.records["desktop-1"] = _device(
        "desktop-1",
        capabilities=[DeviceCapability.LOCAL_AI],
        trust_state=DeviceTrustState.REVOKED,
    )
    response = client.post("/ai/relay/jobs", json=_request_envelope())
    assert response.status_code == 409

    devices.records["desktop-1"] = _device("desktop-1", capabilities=[])
    response = client.post("/ai/relay/jobs", json=_request_envelope())
    assert response.status_code == 409


def test_result_must_be_submitted_by_original_target_for_original_requester() -> None:
    phone, _, _, app = _client("phone-1")
    assert phone.post("/ai/relay/jobs", json=_request_envelope()).status_code == 200

    wrong_result = phone.post("/ai/relay/results", json=_result_envelope())
    assert wrong_result.status_code == 403

    app.dependency_overrides[get_active_subject] = lambda: AuthenticatedSubject(
        account_id="account-1", device_id="desktop-1"
    )
    desktop = TestClient(app)
    payload = _result_envelope() | {"target_device_id": "phone-2"}
    response = desktop.post("/ai/relay/results", json=payload)
    assert response.status_code == 404
