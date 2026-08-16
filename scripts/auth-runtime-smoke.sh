#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT/services/api"

uv run python - <<'PY'
import asyncio
import uuid

from fastapi import HTTPException
from sqlalchemy import delete, text

from app.core.database import async_session_factory, engine
from app.core.schema_compat import ensure_schema_compatibility
from app.core.security import authenticated_subject_from_token
from app.db.models import Account, AccountAuthFlow, AccountSession, Base, Device
from app.modules.auth.flows import SqlAlchemyAuthFlowStore
from app.modules.auth.sessions import SqlAlchemySessionRegistry


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_schema_compatibility(conn)

    account_id = str(uuid.uuid4())
    device_id = str(uuid.uuid4())
    phone = f"+1998{uuid.uuid4().int % 10_000_000_000:010d}"
    try:
        async with async_session_factory() as db:
            db.add(Account(id=account_id, phone_e164=phone, display_name="auth-runtime-smoke"))
            db.add(
                Device(
                    id=device_id,
                    account_id=account_id,
                    display_name="auth-runtime-smoke-device",
                    platform="linux",
                    public_key="auth-runtime-smoke-public-key",
                    trust_state="trusted",
                    capabilities=[],
                    is_default_compute_node=False,
                    key_version=1,
                    protocol_version=1,
                )
            )
            await db.commit()

        async with async_session_factory() as db_a:
            issued = await SqlAlchemySessionRegistry(db_a).issue(
                account_id=account_id,
                device_id=device_id,
            )
            flow = await SqlAlchemyAuthFlowStore(db_a).create_login(
                phone_e164=phone,
                account_id=account_id,
                server_state="opaque-runtime-smoke-state",
            )

        subject = authenticated_subject_from_token(issued.access_token)
        assert subject is not None

        # A second DB session stands in for another API worker / a hot reload.
        async with async_session_factory() as db_b:
            sessions_b = SqlAlchemySessionRegistry(db_b)
            assert await sessions_b.is_access_active(issued.access_token, subject=subject)
            refreshed = await sessions_b.refresh(issued.refresh_token)
            assert refreshed is not None
            consumed = await SqlAlchemyAuthFlowStore(db_b).consume_login(flow.flow_id)
            assert consumed.server_state == "opaque-runtime-smoke-state"

        refreshed_subject = authenticated_subject_from_token(refreshed.access_token)
        assert refreshed_subject is not None
        async with async_session_factory() as db_c:
            sessions_c = SqlAlchemySessionRegistry(db_c)
            assert await sessions_c.is_access_active(issued.access_token, subject=subject)
            assert await sessions_c.is_access_active(
                refreshed.access_token,
                subject=refreshed_subject,
            )
            assert await sessions_c.revoke_access(refreshed.access_token)
            try:
                await SqlAlchemyAuthFlowStore(db_c).consume_login(flow.flow_id)
            except HTTPException as exc:
                assert exc.status_code == 400
            else:
                raise AssertionError("OPAQUE flow was consumed twice")

        async with async_session_factory() as db_d:
            sessions_d = SqlAlchemySessionRegistry(db_d)
            assert not await sessions_d.is_access_active(issued.access_token, subject=subject)
            assert not await sessions_d.is_access_active(
                refreshed.access_token,
                subject=refreshed_subject,
            )
            if db_d.bind is not None and db_d.bind.dialect.name == "postgresql":
                publication = await db_d.execute(
                    text(
                        "SELECT schemaname || '.' || tablename "
                        "FROM pg_publication_tables WHERE pubname = 'powersync' ORDER BY 1"
                    )
                )
                assert publication.scalars().all() == ["public.encrypted_entities"]

        print(
            "AUTH_RUNTIME_SMOKE=PASS "
            "shared_session=true refresh_rotation=true global_revoke=true "
            "shared_opaque_flow=true one_time_flow=true publication_scoped=true"
        )
    finally:
        async with async_session_factory() as db:
            await db.execute(delete(AccountAuthFlow).where(AccountAuthFlow.account_id == account_id))
            await db.execute(delete(AccountSession).where(AccountSession.account_id == account_id))
            await db.execute(delete(Device).where(Device.id == device_id))
            await db.execute(delete(Account).where(Account.id == account_id))
            await db.commit()


asyncio.run(main())
PY
