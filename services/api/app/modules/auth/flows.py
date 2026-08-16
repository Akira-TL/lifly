from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from fastapi import Depends, HTTPException
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import AccountAuthFlow


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


class AuthFlowStoreProtocol(Protocol):
    async def create_registration(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        server_state: str,
    ) -> RegistrationFlow: ...

    async def consume_registration(self, flow_id: str) -> RegistrationFlow: ...

    async def create_login(
        self,
        *,
        phone_e164: str,
        account_id: str | None,
        server_state: str,
    ) -> LoginFlow: ...

    async def consume_login(self, flow_id: str) -> LoginFlow: ...


class AuthFlowStore:
    """In-memory OPAQUE flow store used as an explicit test double."""

    def __init__(self, *, ttl_seconds: int = 300) -> None:
        self._ttl = timedelta(seconds=ttl_seconds)
        self._registrations: dict[str, RegistrationFlow] = {}
        self._logins: dict[str, LoginFlow] = {}

    async def create_registration(
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

    async def consume_registration(self, flow_id: str) -> RegistrationFlow:
        self._prune()
        flow = self._registrations.pop(flow_id, None)
        if flow is None:
            raise HTTPException(status_code=400, detail="Invalid or expired auth flow")
        return flow

    async def create_login(
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

    async def consume_login(self, flow_id: str) -> LoginFlow:
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


class SqlAlchemyAuthFlowStore:
    """Durable one-time OPAQUE flow state shared across API workers."""

    def __init__(self, db: AsyncSession, *, ttl_seconds: int = 300) -> None:
        self._db = db
        self._ttl = timedelta(seconds=ttl_seconds)

    async def create_registration(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        server_state: str,
    ) -> RegistrationFlow:
        now = datetime.now(timezone.utc)
        await self._prune(now)
        flow = RegistrationFlow(
            flow_id=str(uuid.uuid4()),
            phone_e164=phone_e164,
            display_name=display_name,
            server_state=server_state,
            expires_at=now + self._ttl,
        )
        self._db.add(
            AccountAuthFlow(
                id=flow.flow_id,
                flow_type="registration",
                phone_e164=flow.phone_e164,
                display_name=flow.display_name,
                server_state=flow.server_state,
                expires_at=flow.expires_at,
            )
        )
        await self._db.commit()
        return flow

    async def consume_registration(self, flow_id: str) -> RegistrationFlow:
        model = await self._consume(flow_id, "registration")
        return RegistrationFlow(
            flow_id=model.id,
            phone_e164=model.phone_e164,
            display_name=model.display_name,
            server_state=model.server_state,
            expires_at=model.expires_at,
        )

    async def create_login(
        self,
        *,
        phone_e164: str,
        account_id: str | None,
        server_state: str,
    ) -> LoginFlow:
        now = datetime.now(timezone.utc)
        await self._prune(now)
        flow = LoginFlow(
            flow_id=str(uuid.uuid4()),
            phone_e164=phone_e164,
            account_id=account_id,
            server_state=server_state,
            expires_at=now + self._ttl,
        )
        self._db.add(
            AccountAuthFlow(
                id=flow.flow_id,
                flow_type="login",
                phone_e164=flow.phone_e164,
                account_id=flow.account_id,
                server_state=flow.server_state,
                expires_at=flow.expires_at,
            )
        )
        await self._db.commit()
        return flow

    async def consume_login(self, flow_id: str) -> LoginFlow:
        model = await self._consume(flow_id, "login")
        return LoginFlow(
            flow_id=model.id,
            phone_e164=model.phone_e164,
            account_id=model.account_id,
            server_state=model.server_state,
            expires_at=model.expires_at,
        )

    async def _consume(self, flow_id: str, flow_type: str) -> AccountAuthFlow:
        result = await self._db.execute(
            select(AccountAuthFlow)
            .where(
                AccountAuthFlow.id == flow_id,
                AccountAuthFlow.flow_type == flow_type,
            )
            .with_for_update()
        )
        model = result.scalar_one_or_none()
        now = datetime.now(timezone.utc)
        if model is None:
            await self._db.rollback()
            raise HTTPException(status_code=400, detail="Invalid or expired auth flow")
        if model.expires_at <= now:
            await self._db.delete(model)
            await self._db.commit()
            raise HTTPException(status_code=400, detail="Invalid or expired auth flow")
        # Delete before returning so the transcript is one-time even when the
        # caller's PAKE finish later fails authentication.
        await self._db.delete(model)
        await self._db.commit()
        return model

    async def _prune(self, now: datetime) -> None:
        await self._db.execute(
            delete(AccountAuthFlow).where(AccountAuthFlow.expires_at <= now)
        )


async def get_auth_flow_store(
    db: AsyncSession = Depends(get_db),
) -> AuthFlowStoreProtocol:
    return SqlAlchemyAuthFlowStore(db)
