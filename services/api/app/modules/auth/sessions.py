from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from fastapi import Depends, Header, HTTPException
from jose import jwt

from app.core.config import settings
from app.core.security import AuthenticatedSubject, authenticated_subject_from_token

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
    """Mint a foundation-compatible access JWT with unique session identity."""

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


@dataclass(frozen=True, slots=True)
class SessionTokens:
    account_id: str
    device_id: str | None
    access_token: str
    refresh_token: str
    access_expires_at: datetime
    refresh_expires_at: datetime


@dataclass(slots=True)
class _SessionRecord:
    session_id: str
    account_id: str
    device_id: str | None
    refresh_hash: str
    refresh_expires_at: datetime
    access_hashes: set[str] = field(default_factory=set)
    revoked: bool = False


class SessionRegistry:
    """Demo session registry with rotation and revocation semantics.

    The registry is intentionally process-local because the foundation model has no
    session table yet. Callers still receive normal access JWTs so shared business
    endpoints can adopt the same authenticated subject contract. A production
    integration must move this registry to durable/shared storage and make the
    central auth dependency consult it for revocation.
    """

    def __init__(self) -> None:
        self._sessions: dict[str, _SessionRecord] = {}
        self._access_to_session: dict[str, str] = {}
        self._refresh_to_session: dict[str, str] = {}

    def issue(self, *, account_id: str, device_id: str | None = None) -> SessionTokens:
        now = datetime.now(timezone.utc)
        session_id = str(uuid.uuid4())
        access_token, access_expires_at = _create_session_access_token(
            account_id=account_id,
            device_id=device_id,
            session_id=session_id,
            now=now,
        )
        refresh_token = _REFRESH_PREFIX + secrets.token_urlsafe(48)
        record = _SessionRecord(
            session_id=session_id,
            account_id=account_id,
            device_id=device_id,
            refresh_hash=_token_hash(refresh_token),
            refresh_expires_at=now + timedelta(days=settings.jwt_refresh_expire_days),
        )
        access_hash = _token_hash(access_token)
        record.access_hashes.add(access_hash)
        self._sessions[record.session_id] = record
        self._access_to_session[access_hash] = record.session_id
        self._refresh_to_session[record.refresh_hash] = record.session_id
        self._prune(now)
        return SessionTokens(
            account_id=account_id,
            device_id=device_id,
            access_token=access_token,
            refresh_token=refresh_token,
            access_expires_at=access_expires_at,
            refresh_expires_at=record.refresh_expires_at,
        )

    def refresh(self, refresh_token: str) -> SessionTokens | None:
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
        new_refresh_hash = _token_hash(new_refresh)
        record.refresh_hash = new_refresh_hash
        self._refresh_to_session[new_refresh_hash] = session_id

        access_token, access_expires_at = _create_session_access_token(
            account_id=record.account_id,
            device_id=record.device_id,
            session_id=record.session_id,
            now=now,
        )
        access_hash = _token_hash(access_token)
        record.access_hashes.add(access_hash)
        self._access_to_session[access_hash] = session_id
        return SessionTokens(
            account_id=record.account_id,
            device_id=record.device_id,
            access_token=access_token,
            refresh_token=new_refresh,
            access_expires_at=access_expires_at,
            refresh_expires_at=record.refresh_expires_at,
        )

    def is_access_active(
        self, token: str, *, subject: AuthenticatedSubject | None = None
    ) -> bool:
        now = datetime.now(timezone.utc)
        self._prune(now)
        access_hash = _token_hash(token)
        session_id = self._access_to_session.get(access_hash)
        if session_id is None:
            return False
        record = self._sessions.get(session_id)
        if record is None or record.revoked:
            return False
        if subject is not None and (
            record.account_id != subject.account_id
            or record.device_id != subject.device_id
        ):
            return False
        return True

    def revoke_access(self, access_token: str) -> bool:
        session_id = self._access_to_session.get(_token_hash(access_token))
        if session_id is None:
            return False
        record = self._sessions.get(session_id)
        if record is None:
            return False
        self._revoke_record(record)
        return True

    def revoke_device(self, *, account_id: str, device_id: str) -> int:
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

    def _revoke_record(self, record: _SessionRecord) -> None:
        record.revoked = True
        self._refresh_to_session.pop(record.refresh_hash, None)
        for access_hash in record.access_hashes:
            self._access_to_session.pop(access_hash, None)

    def _prune(self, now: datetime) -> None:
        expired = [
            session_id
            for session_id, record in self._sessions.items()
            if record.refresh_expires_at <= now
        ]
        for session_id in expired:
            record = self._sessions.pop(session_id)
            self._refresh_to_session.pop(record.refresh_hash, None)
            for access_hash in record.access_hashes:
                self._access_to_session.pop(access_hash, None)


_default_session_registry = SessionRegistry()


def get_session_registry() -> SessionRegistry:
    return _default_session_registry


def bearer_token(authorization: str = Header(...)) -> str:
    prefix = "Bearer "
    if not authorization.startswith(prefix):
        raise HTTPException(status_code=401, detail="Invalid token")
    token = authorization[len(prefix) :].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Invalid token")
    return token


def get_active_subject(
    token: str = Depends(bearer_token),
    sessions: SessionRegistry = Depends(get_session_registry),
) -> AuthenticatedSubject:
    subject = authenticated_subject_from_token(
        token,
        allowed_types=frozenset({"access"}),
    )
    if subject is None or not sessions.is_access_active(token, subject=subject):
        raise HTTPException(status_code=401, detail="Invalid or revoked token")
    return subject


def get_active_account_id(
    subject: AuthenticatedSubject = Depends(get_active_subject),
) -> str:
    """Return the immutable Account identity for public business routes."""

    return subject.account_id
