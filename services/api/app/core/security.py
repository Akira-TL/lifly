from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Mapping

from fastapi import Header, HTTPException
from jose import JWTError, jwt
from passlib.context import CryptContext

from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


@dataclass(frozen=True, slots=True)
class AuthenticatedSubject:
    """Identity seam injected into authenticated cloud operations.

    ``account_id`` is the immutable cloud identity. During v0.9.0 the legacy
    business ``user_id`` partition is canonically the same value. ``device_id``
    identifies one Account-owned client instance and is never interchangeable
    with the Account identity.
    """

    account_id: str
    device_id: str | None = None

    @property
    def user_id(self) -> str:
        return self.account_id

    def token_claims(self) -> dict[str, str]:
        claims = {
            "sub": self.account_id,
            "account_id": self.account_id,
            "user_id": self.user_id,
        }
        if self.device_id is not None:
            claims["device_id"] = self.device_id
        return claims


# Legacy v0.8.x compatibility only. New Account authentication must use the
# PAKE/aPAKE adapter owned by the v0.9.0 auth module rather than these helpers.
def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def create_access_token(
    user_id: str,
    expires_delta: timedelta | None = None,
    *,
    device_id: str | None = None,
) -> str:
    subject = AuthenticatedSubject(account_id=user_id, device_id=device_id)
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.jwt_expire_minutes)
    )
    return jwt.encode(
        {**subject.token_claims(), "exp": expire, "type": "access"},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def create_refresh_token(user_id: str, *, device_id: str | None = None) -> str:
    subject = AuthenticatedSubject(account_id=user_id, device_id=device_id)
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_expire_days)
    return jwt.encode(
        {**subject.token_claims(), "exp": expire, "type": "refresh"},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def decode_token(token: str) -> dict[str, object] | None:
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    except JWTError:
        return None
    return dict(payload)


def authenticated_subject_from_payload(
    payload: Mapping[str, object],
) -> AuthenticatedSubject | None:
    sub = payload.get("sub")
    account_claim = payload.get("account_id")
    user_claim = payload.get("user_id")
    device_claim = payload.get("device_id")

    account_id = account_claim if isinstance(account_claim, str) else sub
    if not isinstance(account_id, str) or not account_id:
        return None
    if isinstance(sub, str) and sub and sub != account_id:
        return None
    if isinstance(user_claim, str) and user_claim and user_claim != account_id:
        return None
    if device_claim is not None and not isinstance(device_claim, str):
        return None

    return AuthenticatedSubject(account_id=account_id, device_id=device_claim)


def authenticated_subject_from_token(
    token: str,
    *,
    allowed_types: frozenset[str] = frozenset({"access", "api"}),
) -> AuthenticatedSubject | None:
    payload = decode_token(token)
    if payload is None or payload.get("type") not in allowed_types:
        return None
    return authenticated_subject_from_payload(payload)


def get_authenticated_subject(authorization: str = Header(...)) -> AuthenticatedSubject:
    """FastAPI dependency seam for authenticated Account identity injection.

    This validates token identity claims only. Account/session revocation and
    Device Registry state remain the auth/device module's responsibility.
    """

    token = authorization.removeprefix("Bearer ")
    subject = authenticated_subject_from_token(token)
    if subject is None:
        raise HTTPException(status_code=401, detail="Invalid token")
    return subject


def create_api_token(
    user_id: str,
    name: str = "default",
    *,
    device_id: str | None = None,
) -> tuple[str, str]:
    token_id = str(uuid.uuid4())
    prefix = "lifly_mcp_"
    subject = AuthenticatedSubject(account_id=user_id, device_id=device_id)
    token = prefix + jwt.encode(
        {
            **subject.token_claims(),
            "token_id": token_id,
            "name": name,
            "type": "api",
        },
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )
    return token_id, token
