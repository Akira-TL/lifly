from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Protocol

from fastapi import Depends, Header, HTTPException
from jose import JWTError, jwt
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import async_session_factory, get_db
from app.core.security import AuthenticatedSubject, authenticated_subject_from_token
from app.db.models import AccountSession

_REFRESH_PREFIX = "lifly_refresh_"


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _create_session_access_token(
    *,
    account_id: str,
    device_id: str | None,
    session_id: str,
    now: datetime,
) -> tuple[str, datetime]:
    """Mint a foundation-compatible access JWT with durable session identity."""

    expires_at = now + timedelta(minutes=settings.jwt_expire_minutes)
    subject = AuthenticatedSubject(account_id=account_id, device_id=device_id)
    token = jwt.encode(
        {
            **subject.token_claims(),
            "exp": expires_at,
            "type": "access",
            "sid": session_id,
            "jti": str(uuid.uuid4()),
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    return token, expires_at


def _session_id_from_access_token(token: str) -> str | None:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )
    except JWTError:
        return None
    if payload.get("type") != "access":
        return None
    session_id = payload.get("sid")
    if not isinstance(session_id, str) or not session_id:
        return None
    return session_id


@dataclass(frozen=True, slots=True)
class SessionTokens:
    account_id: str
    device_id: str | None
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime


class SessionStore(Protocol):
    async def issue(
        self, *, account_id: str, device_id: str | None = None
    ) -> SessionTokens: ...

    async def refresh(self, refresh_token: str) -> SessionTokens | None: ...

    async def is_access_active(
        self, token: str, *, subject: AuthenticatedSubject | None = None
    ) -> bool: ...

    async def revoke_access(self, access_token: str) -> bool: ...

    async def revoke_device(self, *, account_id: str, device_id: str) -> int: ...


@dataclass(slots=True)
class _MemorySessionRecord:
    session_id: str
    account_id: str
    device_id: str | None
    refresh_hash: str
    refresh_expires_at: datetime
    revoked: bool = False


class SessionRegistry:
    """In-memory SessionStore used as an explicit test double.

    Production dependencies use :class:`SqlAlchemySessionRegistry`; keeping this
    implementation lets router tests exercise auth semantics without requiring a
    live PostgreSQL instance.
    """

    def __init__(self) -> None:
        self._sessions: dict[str, _MemorySessionRecord] = {}
        self._refresh_to_session: dict[str, str] = {}

    async def issue(
        self, *, account_id: str, device_id: str | None = None
    ) -> SessionTokens:
        now = datetime.now(timezone.utc)
        session_id = str(uuid.uuid4())
        access_token, access_expires_at = _create_session_access_token(
            account_id=account_id,
            device_id=device_id,
            session_id=session_id,
            now=now,
        )
        refresh_token = _REFRESH_PREFIX + secrets.token_urlsafe(48)
        record = _MemorySessionRecord(
            session_id=session_id,
            account_id=account_id,
            device_id=device_id,
            refresh_hash=_token_hash(refresh_token),
            refresh_expires_at=now + timedelta(days=settings.jwt_refresh_expire_days),
        )
        self._sessions[session_id] = record
        self._refresh_to_session[record.refresh_hash] = session_id
        self._prune(now)
        return SessionTokens(
            account_id=account_id,
            device_id=device_id,
            access_token=access_token,
            refresh_token=refresh_token,
            access_expires_at=access_expires_at,
            refresh_expires_at=record.refresh_expires_at,
        )

    async def refresh(self, refresh_token: str) -> SessionTokens | None:
        now = datetime.now(timezone.utc)
        self._prune(now)
        old_refresh_hash = _token_hash(refresh_token)
        session_id = self._refresh_to_session.pop(old_refresh_hash, None)
        if session_id is None:
            return None
        record = self._sessions.get(session_id)
        if (
            record is None
            or record.revoked
            or record.refresh_hash != old_refresh_hash
            or record.refresh_expires_at <= now
        ):
            return None

        new_refresh = _REFRESH_PREFIX + secrets.token_urlsafe(48)
        record.refresh_hash = _token_hash(new_refresh)
        self._refresh_to_session[record.refresh_hash] = session_id
        access_token, access_expires_at = _create_session_access_token(
            account_id=record.account_id,
            device_id=record.device_id,
            session_id=record.session_id,
            now=now,
        )
        return SessionTokens(
            account_id=record.account_id,
            device_id=record.device_id,
            access_token=access_token,
            refresh_token=new_refresh,
            access_expires_at=access_expires_at,
            refresh_expires_at=record.refresh_expires_at,
        )

    async def is_access_active(
        self, token: str, *, subject: AuthenticatedSubject | None = None
    ) -> bool:
        now = datetime.now(timezone.utc)
        self._prune(now)
        session_id = _session_id_from_access_token(token)
        if session_id is None:
            return False
        record = self._sessions.get(session_id)
        if record is None or record.revoked or record.refresh_expires_at <= now:
            return False
        if subject is not None and (
            record.account_id != subject.account_id
            or record.device_id != subject.device_id
        ):
            return False
        return True

    async def revoke_access(self, access_token: str) -> bool:
        session_id = _session_id_from_access_token(access_token)
        if session_id is None:
            return False
        record = self._sessions.get(session_id)
        if record is None or record.revoked:
            return False
        self._revoke_record(record)
        return True

    async def revoke_device(self, *, account_id: str, device_id: str) -> int:
        revoked = 0
        for record in self._sessions.values():
            if (
                not record.revoked
                and record.account_id == account_id
                and record.device_id == device_id
            ):
                self._revoke_record(record)
                revoked += 1
        return revoked

    def _revoke_record(self, record: _MemorySessionRecord) -> None:
        record.revoked = True
        self._refresh_to_session.pop(record.refresh_hash, None)

    def _prune(self, now: datetime) -> None:
        expired = [
            session_id
            for session_id, record in self._sessions.items()
            if record.refresh_expires_at <= now
        ]
        for session_id in expired:
            record = self._sessions.pop(session_id)
            self._refresh_to_session.pop(record.refresh_hash, None)


class SqlAlchemySessionRegistry:
    """Durable SessionStore backed by the shared account database."""

    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def issue(
        self, *, account_id: str, device_id: str | None = None
    ) -> SessionTokens:
        now = datetime.now(timezone.utc)
        session_id = str(uuid.uuid4())
        refresh_token = _REFRESH_PREFIX + secrets.token_urlsafe(48)
        refresh_expires_at = now + timedelta(days=settings.jwt_refresh_expire_days)
        self._db.add(
            AccountSession(
                id=session_id,
                account_id=account_id,
                device_id=device_id,
                refresh_hash=_token_hash(refresh_token),
                refresh_expires_at=refresh_expires_at,
            )
        )
        await self._db.commit()
        access_token, access_expires_at = _create_session_access_token(
            account_id=account_id,
            device_id=device_id,
            session_id=session_id,
            now=now,
        )
        return SessionTokens(
            account_id=account_id,
            device_id=device_id,
            access_token=access_token,
            refresh_token=refresh_token,
            access_expires_at=access_expires_at,
            refresh_expires_at=refresh_expires_at,
        )

    async def refresh(self, refresh_token: str) -> SessionTokens | None:
        now = datetime.now(timezone.utc)
        old_refresh_hash = _token_hash(refresh_token)
        result = await self._db.execute(
            select(AccountSession)
            .where(AccountSession.refresh_hash == old_refresh_hash)
            .with_for_update()
        )
        record = result.scalar_one_or_none()
        if (
            record is None
            or record.revoked_at is not None
            or record.refresh_expires_at <= now
        ):
            await self._db.rollback()
            return None

        new_refresh = _REFRESH_PREFIX + secrets.token_urlsafe(48)
        record.refresh_hash = _token_hash(new_refresh)
        access_token, access_expires_at = _create_session_access_token(
            account_id=record.account_id,
            device_id=record.device_id,
            session_id=record.id,
            now=now,
        )
        await self._db.commit()
        return SessionTokens(
            account_id=record.account_id,
            device_id=record.device_id,
            access_token=access_token,
            refresh_token=new_refresh,
            access_expires_at=access_expires_at,
            refresh_expires_at=record.refresh_expires_at,
        )

    async def is_access_active(
        self, token: str, *, subject: AuthenticatedSubject | None = None
    ) -> bool:
        session_id = _session_id_from_access_token(token)
        if session_id is None:
            return False
        result = await self._db.execute(
            select(AccountSession).where(AccountSession.id == session_id)
        )
        record = result.scalar_one_or_none()
        now = datetime.now(timezone.utc)
        if (
            record is None
            or record.revoked_at is not None
            or record.refresh_expires_at <= now
        ):
            return False
        if subject is not None and (
            record.account_id != subject.account_id
            or record.device_id != subject.device_id
        ):
            return False
        return True

    async def revoke_access(self, access_token: str) -> bool:
        session_id = _session_id_from_access_token(access_token)
        if session_id is None:
            return False
        result = await self._db.execute(
            select(AccountSession)
            .where(AccountSession.id == session_id)
            .with_for_update()
        )
        record = result.scalar_one_or_none()
        if record is None or record.revoked_at is not None:
            await self._db.rollback()
            return False
        record.revoked_at = datetime.now(timezone.utc)
        await self._db.commit()
        return True

    async def revoke_device(self, *, account_id: str, device_id: str) -> int:
        now = datetime.now(timezone.utc)
        result = await self._db.execute(
            update(AccountSession)
            .where(
                AccountSession.account_id == account_id,
                AccountSession.device_id == device_id,
                AccountSession.revoked_at.is_(None),
            )
            .values(revoked_at=now)
        )
        await self._db.commit()
        return int(result.rowcount or 0)


async def get_session_registry(
    db: AsyncSession = Depends(get_db),
) -> SessionStore:
    return SqlAlchemySessionRegistry(db)


async def is_access_active_persistent(
    token: str, *, subject: AuthenticatedSubject
) -> bool:
    """Shared auth check for non-FastAPI integrations such as Cloud MCP."""

    async with async_session_factory() as db:
        return await SqlAlchemySessionRegistry(db).is_access_active(
            token,
            subject=subject,
        )


def bearer_token(authorization: str | None = Header(default=None)) -> str:
    prefix = "Bearer "
    if authorization is None or not authorization.startswith(prefix):
        raise HTTPException(status_code=401, detail="Invalid token")
    token = authorization[len(prefix) :].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Invalid token")
    return token


async def get_active_subject(
    token: str = Depends(bearer_token),
    sessions: SessionStore = Depends(get_session_registry),
) -> AuthenticatedSubject:
    subject = authenticated_subject_from_token(
        token,
        allowed_types=frozenset({"access"}),
    )
    if subject is None or not await sessions.is_access_active(token, subject=subject):
        raise HTTPException(status_code=401, detail="Invalid or revoked token")
    return subject


def get_active_account_id(
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> str:
    """Return the immutable Account identity for public business routes."""

    return subject.account_id
