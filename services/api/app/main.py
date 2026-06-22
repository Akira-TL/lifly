from __future__ import annotations

import contextlib

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import engine
from app.core.config import settings
from app.db.models import Base
from app.modules.memos.router import router as memo_router
from app.modules.ledger.router import router as ledger_router
from app.modules.tasks.router import router as task_router
from app.modules.auth.router import router as auth_router
from app.modules.trash import router as trash_router
from app.modules.assets.router import router as assets_router
from app.modules.mcp.router import router as mcp_router
from app.modules.mcp.cloud_server import cloud_mcp


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
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
    title="Lifily API",
    version="0.4.0",
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
app.include_router(memo_router, prefix="/api/v1/memos", tags=["memos"])
app.include_router(ledger_router, prefix="/api/v1/ledger", tags=["ledger"])
app.include_router(task_router, prefix="/api/v1/tasks", tags=["tasks"])
app.include_router(assets_router, prefix="/api/v1/assets", tags=["assets"])
app.include_router(mcp_router, prefix="/api/v1/mcp", tags=["mcp"])
app.include_router(trash_router, prefix="/api/v1", tags=["audit", "trash"])

# MCP Streamable HTTP endpoint (Cloud MCP)
app.mount("/", cloud_mcp.streamable_http_app())


@app.get("/api/v1/health")
async def health():
    return {"status": "ok", "version": "0.4.0", "port": settings.api_port}
