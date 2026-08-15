from __future__ import annotations

import asyncio
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

OPAQUE_PROTOCOL = "opaque-rfc9807"
OPAQUE_PROTOCOL_VERSION = 1
OPAQUE_HELPER_ENV = "LIFLY_OPAQUE_SERVER_HELPER"


class PakeUnavailable(RuntimeError):
    pass


class PakeProtocolError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class PakeServerStart:
    server_response: str
    server_state: str


class PakeServerAdapter(Protocol):
    protocol: str
    protocol_version: int

    async def registration_start(
        self, *, identifier: str, client_request: str
    ) -> PakeServerStart: ...

    async def registration_finish(
        self, *, identifier: str, server_state: str, client_upload: str
    ) -> str: ...

    async def login_start(
        self,
        *,
        identifier: str,
        credential_record: str | None,
        client_request: str,
    ) -> PakeServerStart: ...

    async def login_finish(
        self, *, identifier: str, server_state: str, client_finish: str
    ) -> bool: ...


class UnavailableOpaqueServerAdapter:
    protocol = OPAQUE_PROTOCOL
    protocol_version = OPAQUE_PROTOCOL_VERSION

    async def registration_start(
        self, *, identifier: str, client_request: str
    ) -> PakeServerStart:
        raise self._error()

    async def registration_finish(
        self, *, identifier: str, server_state: str, client_upload: str
    ) -> str:
        raise self._error()

    async def login_start(
        self,
        *,
        identifier: str,
        credential_record: str | None,
        client_request: str,
    ) -> PakeServerStart:
        raise self._error()

    async def login_finish(
        self, *, identifier: str, server_state: str, client_finish: str
    ) -> bool:
        raise self._error()

    @staticmethod
    def _error() -> PakeUnavailable:
        return PakeUnavailable(
            "OPAQUE helper is not configured; plaintext-password fallback is disabled"
        )


class OpaqueHelperServerAdapter:
    """JSON-over-stdio adapter for an RFC 9807 OPAQUE implementation.

    The helper owns all OPAQUE cryptography and long-lived server setup material.
    Lifly only transports opaque protocol messages and stores the credential record.
    A helper should be backed by an audited/maintained implementation such as
    ``opaque-ke`` rather than reimplementing PAKE primitives in Python.
    """

    protocol = OPAQUE_PROTOCOL
    protocol_version = OPAQUE_PROTOCOL_VERSION

    def __init__(self, helper_path: str, *, timeout_seconds: float = 5.0) -> None:
        path = Path(helper_path).expanduser()
        if not path.is_file():
            raise PakeUnavailable(f"OPAQUE helper does not exist: {path}")
        self._helper_path = str(path)
        self._timeout_seconds = timeout_seconds

    async def registration_start(
        self, *, identifier: str, client_request: str
    ) -> PakeServerStart:
        result = await self._invoke(
            "registration_start",
            identifier=identifier,
            client_request=client_request,
        )
        return PakeServerStart(
            server_response=_required_string(result, "server_response"),
            server_state=_required_string(result, "server_state"),
        )

    async def registration_finish(
        self, *, identifier: str, server_state: str, client_upload: str
    ) -> str:
        result = await self._invoke(
            "registration_finish",
            identifier=identifier,
            server_state=server_state,
            client_upload=client_upload,
        )
        return _required_string(result, "credential_record")

    async def login_start(
        self,
        *,
        identifier: str,
        credential_record: str | None,
        client_request: str,
    ) -> PakeServerStart:
        result = await self._invoke(
            "login_start",
            identifier=identifier,
            credential_record=credential_record,
            client_request=client_request,
        )
        return PakeServerStart(
            server_response=_required_string(result, "server_response"),
            server_state=_required_string(result, "server_state"),
        )

    async def login_finish(
        self, *, identifier: str, server_state: str, client_finish: str
    ) -> bool:
        result = await self._invoke(
            "login_finish",
            identifier=identifier,
            server_state=server_state,
            client_finish=client_finish,
        )
        authenticated = result.get("authenticated")
        if not isinstance(authenticated, bool):
            raise PakeProtocolError("OPAQUE helper omitted boolean authenticated")
        return authenticated

    async def _invoke(self, operation: str, **payload: object) -> dict[str, object]:
        request = json.dumps(
            {
                "protocol": self.protocol,
                "protocol_version": self.protocol_version,
                "operation": operation,
                **payload,
            },
            separators=(",", ":"),
        ).encode("utf-8")
        try:
            process = await asyncio.create_subprocess_exec(
                self._helper_path,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                process.communicate(input=request), timeout=self._timeout_seconds
            )
        except (OSError, TimeoutError) as exc:
            raise PakeUnavailable("OPAQUE helper execution failed") from exc
        if process.returncode != 0:
            detail = stderr.decode("utf-8", errors="replace")[:256]
            raise PakeUnavailable(f"OPAQUE helper failed: {detail or process.returncode}")
        try:
            result = json.loads(stdout.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise PakeProtocolError("OPAQUE helper returned invalid JSON") from exc
        if not isinstance(result, dict):
            raise PakeProtocolError("OPAQUE helper returned non-object JSON")
        return result


def _required_string(value: dict[str, object], key: str) -> str:
    item = value.get(key)
    if not isinstance(item, str) or not item:
        raise PakeProtocolError(f"OPAQUE helper omitted {key}")
    return item


def _build_default_adapter() -> PakeServerAdapter:
    helper = os.getenv(OPAQUE_HELPER_ENV, "").strip()
    if not helper:
        return UnavailableOpaqueServerAdapter()
    try:
        return OpaqueHelperServerAdapter(helper)
    except PakeUnavailable:
        return UnavailableOpaqueServerAdapter()


_default_adapter = _build_default_adapter()


def get_pake_server_adapter() -> PakeServerAdapter:
    return _default_adapter
