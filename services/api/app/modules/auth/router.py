from __future__ import annotations

from datetime import datetime, timezone

import hashlib
from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    create_api_token,
    decode_token,
)
from app.db.models import User, ApiToken

router = APIRouter()


# ─── Register ────────────────────────────────────────────────────────────────

@router.post("/register")
async def register(email: str, password: str, display_name: str | None = None, db: AsyncSession = Depends(get_db)):
    existing = await db.execute(select(User).where(User.email == email))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=email,
        hashed_password=hash_password(password),
        display_name=display_name or email,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    access = create_access_token(user.id)
    refresh = create_refresh_token(user.id)
    return {
        "user_id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "access_token": access,
        "refresh_token": refresh,
    }


# ─── Login ───────────────────────────────────────────────────────────────────

@router.post("/login")
async def login(email: str, password: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).where(User.email == email, User.is_active == True))
    user = result.scalar_one_or_none()
    if not user or not verify_password(password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    access = create_access_token(user.id)
    refresh = create_refresh_token(user.id)
    return {
        "user_id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "access_token": access,
        "refresh_token": refresh,
    }


# ─── Refresh ─────────────────────────────────────────────────────────────────

@router.post("/refresh")
async def refresh(refresh_token: str, db: AsyncSession = Depends(get_db)):
    payload = decode_token(refresh_token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user_id = payload.get("sub")
    result = await db.execute(select(User).where(User.id == user_id, User.is_active == True))
    if not result.scalar_one_or_none():
        raise HTTPException(status_code=401, detail="User not found")

    access = create_access_token(user_id)
    new_refresh = create_refresh_token(user_id)
    return {"access_token": access, "refresh_token": new_refresh}


# ─── API Token management ────────────────────────────────────────────────────

@router.post("/api-tokens")
async def create_token(name: str, authorization: str = Header(...), db: AsyncSession = Depends(get_db)):
    payload = _verify_auth(authorization)
    token_id, token_str = create_api_token(payload["sub"], name)
    token_hash = hashlib.sha256(token_str.encode()).hexdigest()

    db.add(ApiToken(id=token_id, user_id=payload["sub"], name=name, token_hash=token_hash))
    await db.commit()
    return {"token_id": token_id, "token": token_str, "name": name}


@router.get("/api-tokens")
async def list_tokens(authorization: str = Header(...), db: AsyncSession = Depends(get_db)):
    payload = _verify_auth(authorization)
    result = await db.execute(
        select(ApiToken).where(ApiToken.user_id == payload["sub"], ApiToken.is_revoked == False)
    )
    tokens = result.scalars().all()
    return {
        "tokens": [
            {"id": t.id, "name": t.name, "last_used_at": t.last_used_at, "created_at": t.created_at}
            for t in tokens
        ]
    }


@router.post("/api-tokens/{token_id}/revoke")
async def revoke_token(token_id: str, authorization: str = Header(...), db: AsyncSession = Depends(get_db)):
    payload = _verify_auth(authorization)
    result = await db.execute(
        select(ApiToken).where(ApiToken.id == token_id, ApiToken.user_id == payload["sub"])
    )
    token = result.scalar_one_or_none()
    if not token:
        raise HTTPException(status_code=404, detail="Token not found")
    token.is_revoked = True
    await db.commit()
    return {"ok": True}


# ─── Helpers ─────────────────────────────────────────────────────────────────

def _verify_auth(authorization: str) -> dict:
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing authorization header")
    token = authorization.removeprefix("Bearer ")
    payload = decode_token(token)
    if not payload or payload.get("type") not in ("access", "api"):
        raise HTTPException(status_code=401, detail="Invalid token")
    return payload


async def get_current_user(authorization: str = Header(...), db: AsyncSession = Depends(get_db)) -> dict:
    payload = _verify_auth(authorization)
    return {"user_id": payload["sub"]}
