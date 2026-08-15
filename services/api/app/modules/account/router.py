from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import AuthenticatedSubject
from app.modules.account.contracts import AccountIdentity
from app.modules.account.repository import AccountRepository, get_account_repository
from app.modules.auth.sessions import get_active_subject

router = APIRouter()


@router.get("/me", response_model=AccountIdentity)
async def get_account_profile(
    subject: AuthenticatedSubject = Depends(get_active_subject),
    accounts: AccountRepository = Depends(get_account_repository),
) -> AccountIdentity:
    account = await accounts.find_by_id(subject.account_id)
    if account is None or account.account_status != "active":
        raise HTTPException(status_code=404, detail="Account not found")
    return AccountIdentity(
        account_id=account.account_id,
        phone_e164=account.phone_e164,
        display_name=account.display_name,
        account_status=account.account_status,
        plan=account.plan,
    )
