from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException


@dataclass(frozen=True, slots=True)
class RegistrationFlow:
    flow_id: str
    phone_e164: str
    display_name: str | None
    server_state: str
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class LoginFlow:
    flow_id: str
    phone_e164: str
    account_id: str | None
    server_state: str
    expires_at: datetime


class AuthFlowStore:
    """Short-lived one-time PAKE transcript state for one API process."""

    def __init__(self, *, ttl_seconds: int = 300) -> None:
        self._ttl = timedelta(seconds=ttl_seconds)
        self._registrations: dict[str, RegistrationFlow] = {}
        self._logins: dict[str, LoginFlow] = {}

    def create_registration(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        server_state: str,
    ) -> RegistrationFlow:
        self._prune()
        now = datetime.now(timezone.utc)
        flow = RegistrationFlow(
            flow_id=str(uuid.uuid4()),
            phone_e164=phone_e164,
            display_name=display_name,
            server_state=server_state,
            expires_at=now + self._ttl,
        )
        self._registrations[flow.flow_id] = flow
        return flow

    def consume_registration(self, flow_id: str) -> RegistrationFlow:
        self._prune()
        flow = self._registrations.pop(flow_id, None)
        if flow is None:
            raise HTTPException(status_code=400, detail="Invalid or expired auth flow")
        return flow

    def create_login(
        self,
        *,
        phone_e164: str,
        account_id: str | None,
        server_state: str,
    ) -> LoginFlow:
        self._prune()
        now = datetime.now(timezone.utc)
        flow = LoginFlow(
            flow_id=str(uuid.uuid4()),
            phone_e164=phone_e164,
            account_id=account_id,
            server_state=server_state,
            expires_at=now + self._ttl,
        )
        self._logins[flow.flow_id] = flow
        return flow

    def consume_login(self, flow_id: str) -> LoginFlow:
        self._prune()
        flow = self._logins.pop(flow_id, None)
        if flow is None:
            raise HTTPException(status_code=400, detail="Invalid or expired auth flow")
        return flow

    def _prune(self) -> None:
        now = datetime.now(timezone.utc)
        self._registrations = {
            key: value
            for key, value in self._registrations.items()
            if value.expires_at > now
        }
        self._logins = {
            key: value for key, value in self._logins.items() if value.expires_at > now
        }


_default_flow_store = AuthFlowStore()


def get_auth_flow_store() -> AuthFlowStore:
    return _default_flow_store
