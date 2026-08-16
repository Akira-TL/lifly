from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.db.models import Account, AccountAuthCredential


@dataclass(frozen=True, slots=True)
class AccountRecord:
    account_id: str
    phone_e164: str
    display_name: str | None
    account_status: str
    plan: str

    @classmethod
    def from_model(cls, account: Account) -> "AccountRecord":
        return cls(
            account_id=account.id,
            phone_e164=account.phone_e164,
            display_name=account.display_name,
            account_status=account.account_status,
            plan=account.plan,
        )


class AccountAlreadyExists(RuntimeError):
    pass


class AccountRepository(Protocol):
    async def find_by_phone(self, phone_e164: str) -> AccountRecord | None: ...

    async def find_by_id(self, account_id: str) -> AccountRecord | None: ...

    async def get_credential_record(self, account_id: str) -> str | None: ...

    async def create_account(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        credential_record: str,
        commit: bool = True,
    ) -> AccountRecord: ...

    async def commit(self) -> None: ...

    async def rollback(self) -> None: ...


class SqlAlchemyAccountRepository:
    def __init__(self, db: AsyncSession) -> None:
        self._db = db

    async def find_by_phone(self, phone_e164: str) -> AccountRecord | None:
        result = await self._db.execute(
            select(Account).where(Account.phone_e164 == phone_e164)
        )
        account = result.scalar_one_or_none()
        return AccountRecord.from_model(account) if account is not None else None

    async def find_by_id(self, account_id: str) -> AccountRecord | None:
        result = await self._db.execute(select(Account).where(Account.id == account_id))
        account = result.scalar_one_or_none()
        return AccountRecord.from_model(account) if account is not None else None

    async def get_credential_record(self, account_id: str) -> str | None:
        result = await self._db.execute(
            select(AccountAuthCredential).where(
                AccountAuthCredential.account_id == account_id
            )
        )
        credential = result.scalar_one_or_none()
        return credential.credential_record if credential is not None else None

    async def create_account(
        self,
        *,
        phone_e164: str,
        display_name: str | None,
        credential_record: str,
        commit: bool = True,
    ) -> AccountRecord:
        account = Account(phone_e164=phone_e164, display_name=display_name)
        self._db.add(account)
        try:
            await self._db.flush()
            self._db.add(
                AccountAuthCredential(
                    account_id=account.id,
                    protocol="opaque-rfc9807",
                    protocol_version=1,
                    credential_record=credential_record,
                )
            )
            await self._db.flush()
            if commit:
                await self._db.commit()
        except IntegrityError as exc:
            await self._db.rollback()
            raise AccountAlreadyExists from exc
        if commit:
            await self._db.refresh(account)
        return AccountRecord.from_model(account)

    async def commit(self) -> None:
        await self._db.commit()

    async def rollback(self) -> None:
        await self._db.rollback()


async def get_account_repository(
    db: AsyncSession = Depends(get_db),
) -> AccountRepository:
    return SqlAlchemyAccountRepository(db)
