from __future__ import annotations

import contextlib

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import engine
from app.core.config import settings
from app.core.schema_compat import ensure_schema_compatibility
from app.db.models import Base
from app.modules.memos.router import router as memo_router
from app.modules.ledger.router import router as ledger_router
from app.modules.tasks.router import router as task_router
from app.modules.auth.router import router as auth_router
from app.modules.trash import router as trash_router
from app.modules.assets.router import router as assets_router
from app.modules.mcp.router import router as mcp_router
from app.modules.imexport.router import router as imexport_router
from app.modules.search.router import router as search_router
from app.modules.sync.router import router as sync_router
from app.modules.plugins.router import router as plugins_router
from app.modules.mcp.cloud_server import cloud_mcp
from app.modules.account.router import router as account_router
from app.modules.devices.router import router as devices_router
from app.modules.crypto.router import router as crypto_router
from app.modules.ai.router import router as ai_router
from app.modules.ai_relay.router import router as ai_relay_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
            await ensure_schema_compatibility(conn)
    except Exception:
        print("WARN: Database unavailable, skipping table creation")
    # Start MCP session manager
    async with cloud_mcp._session_manager.run():
        yield
    try:
        await engine.dispose()
    except Exception:
        pass


app = FastAPI(
    title="Lifly API",
    version="0.9.0",
    docs_url="/docs",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(account_router, prefix="/api/v1/account", tags=["account"])
app.include_router(devices_router, prefix="/api/v1/devices", tags=["devices"])
app.include_router(crypto_router, prefix="/api/v1/crypto", tags=["crypto"])
app.include_router(ai_router, prefix="/api/v1/ai", tags=["ai"])
app.include_router(ai_relay_router, prefix="/api/v1/ai/relay", tags=["ai-relay"])
app.include_router(memo_router, prefix="/api/v1/memos", tags=["memos"])
app.include_router(ledger_router, prefix="/api/v1/ledger", tags=["ledger"])
app.include_router(task_router, prefix="/api/v1/tasks", tags=["tasks"])
app.include_router(assets_router, prefix="/api/v1/assets", tags=["assets"])
app.include_router(mcp_router, prefix="/api/v1/mcp", tags=["mcp"])
app.include_router(trash_router, prefix="/api/v1", tags=["audit", "trash"])
app.include_router(
    imexport_router, prefix="/api/v1/imexport", tags=["import", "export"]
)
app.include_router(search_router, prefix="/api/v1", tags=["search", "dashboard"])
app.include_router(sync_router, prefix="/api/v1/sync", tags=["sync"])
app.include_router(plugins_router, prefix="/api/v1", tags=["plugins", "robots"])


@app.get("/api/v1/health")
async def health():
    return {"status": "ok", "version": app.version, "port": settings.api_port}


# MCP Streamable HTTP endpoint (Cloud MCP) is mounted last because "/" is a catch-all.
app.mount("/", cloud_mcp.streamable_http_app())
