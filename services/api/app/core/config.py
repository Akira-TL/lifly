from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # API
    api_port: int = 8310

    # Database
    database_url: str = "postgresql+asyncpg://lifly:lifly@localhost:8332/lifly"

    # Redis
    redis_url: str = "redis://localhost:8379/0"

    # MinIO
    minio_endpoint: str = "http://localhost:8300"
    minio_access_key: str = "lifly"
    minio_secret_key: str = "lifly-secret"
    minio_bucket: str = "lifly-assets"

    # PowerSync
    powersync_url: str = "http://localhost:8380"

    # JWT
    jwt_secret: str = "dev-only-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24  # 24h

    # MCP
    mcp_server_url: str = "http://localhost:8787"

    # Paths
    project_root: Path = Path(__file__).resolve().parent.parent.parent


settings = Settings()
