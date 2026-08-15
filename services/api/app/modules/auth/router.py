from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.modules.account.contracts import AccountIdentity
from app.modules.account.repository import (
    AccountAlreadyExists,
    AccountRecord,
    AccountRepository,
    get_account_repository,
)
from app.modules.auth.contracts import (
    AuthSessionResponse,
    AuthStartResponse,
    LoginFinishRequest,
    LoginStartRequest,
    RefreshRequest,
    RegistrationFinishRequest,
    RegistrationStartRequest,
    RevokeResponse,
)
from app.modules.auth.flows import AuthFlowStore, get_auth_flow_store
from app.modules.auth.pake import (
    PakeProtocolError,
    PakeServerAdapter,
    PakeUnavailable,
    get_pake_server_adapter,
)
from app.modules.auth.phone import InvalidPhoneNumber, normalize_phone
from app.modules.auth.sessions import (
    SessionRegistry,
    SessionTokens,
    bearer_token,
    get_session_registry,
)

router = APIRouter()


def _identity(account: AccountRecord) -> AccountIdentity:
    return AccountIdentity(
        account_id=account.account_id,
        phone_e164=account.phone_e164,
        display_name=account.display_name,
        account_status=account.account_status,
        plan=account.plan,
    )


def _session_response(
    account: AccountRecord, tokens: SessionTokens
) -> AuthSessionResponse:
    return AuthSessionResponse(
        account=_identity(account),
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        access_expires_at=tokens.access_expires_at,
        refresh_expires_at=tokens.refresh_expires_at,
    )


def _normalize_or_422(phone: str, region: str | None) -> str:
    try:
        return normalize_phone(phone, region=region)
    except InvalidPhoneNumber as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


async def _pake_call(awaitable):
    try:
        return await awaitable
    except PakeUnavailable as exc:
        raise HTTPException(
            status_code=503,
            detail="Password authentication is temporarily unavailable",
        ) from exc
    except PakeProtocolError as exc:
        raise HTTPException(status_code=502, detail="Password authentication failed") from exc


@router.post("/register/start", response_model=AuthStartResponse)
async def registration_start(
    request: RegistrationStartRequest,
    accounts: AccountRepository = Depends(get_account_repository),
    pake: PakeServerAdapter = Depends(get_pake_server_adapter),
    flows: AuthFlowStore = Depends(get_auth_flow_store),
) -> AuthStartResponse:
    phone_e164 = _normalize_or_422(request.phone, request.region)
    if await accounts.find_by_phone(phone_e164) is not None:
        raise HTTPException(status_code=409, detail="Phone already registered")
    started = await _pake_call(
        pake.registration_start(
            identifier=phone_e164,
            client_request=request.client_request,
        )
    )
    flow = flows.create_registration(
        phone_e164=phone_e164,
        display_name=request.display_name,
        server_state=started.server_state,
    )
    return AuthStartResponse(
        flow_id=flow.flow_id,
        phone_e164=phone_e164,
        server_response=started.server_response,
        expires_at=flow.expires_at,
    )


@router.post("/register/finish", response_model=AuthSessionResponse)
async def registration_finish(
    request: RegistrationFinishRequest,
    accounts: AccountRepository = Depends(get_account_repository),
    pake: PakeServerAdapter = Depends(get_pake_server_adapter),
    flows: AuthFlowStore = Depends(get_auth_flow_store),
    sessions: SessionRegistry = Depends(get_session_registry),
) -> AuthSessionResponse:
    flow = flows.consume_registration(request.flow_id)
    if await accounts.find_by_phone(flow.phone_e164) is not None:
        raise HTTPException(status_code=409, detail="Phone already registered")
    credential_record = await _pake_call(
        pake.registration_finish(
            identifier=flow.phone_e164,
            server_state=flow.server_state,
            client_upload=request.client_upload,
        )
    )
    try:
        account = await accounts.create_account(
            phone_e164=flow.phone_e164,
            display_name=flow.display_name,
            credential_record=credential_record,
        )
    except AccountAlreadyExists as exc:
        raise HTTPException(status_code=409, detail="Phone already registered") from exc
    tokens = sessions.issue(account_id=account.account_id)
    return _session_response(account, tokens)


@router.post("/login/start", response_model=AuthStartResponse)
async def login_start(
    request: LoginStartRequest,
    accounts: AccountRepository = Depends(get_account_repository),
    pake: PakeServerAdapter = Depends(get_pake_server_adapter),
    flows: AuthFlowStore = Depends(get_auth_flow_store),
) -> AuthStartResponse:
    phone_e164 = _normalize_or_422(request.phone, request.region)
    account = await accounts.find_by_phone(phone_e164)
    credential_record = None
    if account is not None:
        credential_record = await accounts.get_credential_record(account.account_id)
    started = await _pake_call(
        pake.login_start(
            identifier=phone_e164,
            credential_record=credential_record,
            client_request=request.client_request,
        )
    )
    flow = flows.create_login(
        phone_e164=phone_e164,
        account_id=account.account_id if account is not None else None,
        server_state=started.server_state,
    )
    return AuthStartResponse(
        flow_id=flow.flow_id,
        phone_e164=phone_e164,
        server_response=started.server_response,
        expires_at=flow.expires_at,
    )


@router.post("/login/finish", response_model=AuthSessionResponse)
async def login_finish(
    request: LoginFinishRequest,
    accounts: AccountRepository = Depends(get_account_repository),
    pake: PakeServerAdapter = Depends(get_pake_server_adapter),
    flows: AuthFlowStore = Depends(get_auth_flow_store),
    sessions: SessionRegistry = Depends(get_session_registry),
) -> AuthSessionResponse:
    flow = flows.consume_login(request.flow_id)
    authenticated = await _pake_call(
        pake.login_finish(
            identifier=flow.phone_e164,
            server_state=flow.server_state,
            client_finish=request.client_finish,
        )
    )
    if not authenticated or flow.account_id is None:
        raise HTTPException(status_code=401, detail="Invalid phone or password")
    account = await accounts.find_by_id(flow.account_id)
    if account is None or account.account_status != "active":
        raise HTTPException(status_code=401, detail="Invalid phone or password")
    tokens = sessions.issue(account_id=account.account_id)
    return _session_response(account, tokens)


@router.post("/refresh", response_model=AuthSessionResponse)
async def refresh_session(
    request: RefreshRequest,
    accounts: AccountRepository = Depends(get_account_repository),
    sessions: SessionRegistry = Depends(get_session_registry),
) -> AuthSessionResponse:
    tokens = sessions.refresh(request.refresh_token)
    if tokens is None:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    account = await accounts.find_by_id(tokens.account_id)
    if account is None or account.account_status != "active":
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    return _session_response(account, tokens)


@router.post("/revoke", response_model=RevokeResponse)
async def revoke_session(
    token: str = Depends(bearer_token),
    sessions: SessionRegistry = Depends(get_session_registry),
) -> RevokeResponse:
    if not sessions.revoke_access(token):
        raise HTTPException(status_code=401, detail="Invalid or revoked token")
    return RevokeResponse()
