#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT/services/api"

uv run python - <<'PY'
import asyncio
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete

from app.core.database import async_session_factory
from app.db.models import Account, AiJob, Device
from app.modules.ai_relay.contracts import AiJobEnvelope, AiJobMessageType
from app.modules.ai_relay.repository import SqlAlchemyAiRelayStore


async def main() -> None:
    account_id = str(uuid.uuid4())
    phone_id = str(uuid.uuid4())
    desktop_id = str(uuid.uuid4())
    job_id = str(uuid.uuid4())
    phone = f"+1997{uuid.uuid4().int % 10_000_000_000:010d}"
    now = datetime.now(timezone.utc)
    try:
        async with async_session_factory() as db:
            db.add(Account(id=account_id, phone_e164=phone, display_name="relay-runtime-smoke"))
            db.add_all(
                [
                    Device(
                        id=phone_id,
                        account_id=account_id,
                        display_name="relay-phone",
                        platform="android",
                        public_key="relay-phone-public-key",
                        trust_state="trusted",
                        capabilities=[],
                        is_default_compute_node=False,
                        key_version=1,
                        protocol_version=1,
                    ),
                    Device(
                        id=desktop_id,
                        account_id=account_id,
                        display_name="relay-desktop",
                        platform="linux",
                        public_key="relay-desktop-public-key",
                        trust_state="trusted",
                        capabilities=["local_ai", "local_mcp"],
                        is_default_compute_node=True,
                        key_version=1,
                        protocol_version=1,
                    ),
                ]
            )
            await db.commit()

        envelope = AiJobEnvelope(
            job_id=job_id,
            account_id=account_id,
            source_device_id=phone_id,
            target_device_id=desktop_id,
            message_type=AiJobMessageType.REQUEST,
            idempotency_key="relay-runtime-smoke",
            expires_at=now + timedelta(minutes=5),
            encryption_version=1,
            nonce="opaque-nonce",
            ciphertext="opaque-ciphertext",
        )
        async with async_session_factory() as db:
            await SqlAlchemyAiRelayStore(db).submit_request(envelope)

        async def claim() -> AiJobEnvelope | None:
            async with async_session_factory() as db:
                return await SqlAlchemyAiRelayStore(db).next_for_target(
                    account_id=account_id,
                    target_device_id=desktop_id,
                    now=now,
                )

        first, second = await asyncio.gather(claim(), claim())
        claimed = [item for item in (first, second) if item is not None]
        assert len(claimed) == 1
        assert claimed[0].job_id == job_id

        async with async_session_factory() as db:
            store = SqlAlchemyAiRelayStore(db)
            await store.mark_failed(account_id=account_id, job_id=job_id)
            assert await store.next_for_target(
                account_id=account_id,
                target_device_id=desktop_id,
                now=now + timedelta(seconds=30),
            ) is None

        print(
            "RELAY_RUNTIME_SMOKE=PASS "
            "concurrent_claim_single=true terminal_failure_not_redelivered=true"
        )
    finally:
        async with async_session_factory() as db:
            await db.execute(delete(AiJob).where(AiJob.account_id == account_id))
            await db.execute(delete(Device).where(Device.account_id == account_id))
            await db.execute(delete(Account).where(Account.id == account_id))
            await db.commit()


asyncio.run(main())
PY
