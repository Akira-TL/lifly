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
    api_port: int = 8210

    # Database
    database_url: str = "postgresql+asyncpg://lifly:lifly@localhost:8200/lifly"

    # Redis
    redis_url: str = "redis://localhost:8201/0"

    # MinIO
    minio_endpoint: str = "http://localhost:8202"
    minio_access_key: str = "lifly"
    minio_secret_key: str = "lifly-secret"
    minio_bucket: str = "lifly-assets"

    # PowerSync
    powersync_url: str = "http://localhost:8204"
    powersync_dev_user_id: str = "local-dev"
    powersync_token_expire_minutes: int = 60

    # Auth/session compatibility seam. OPAQUE/aPAKE protocol state belongs to
    # app.modules.auth; these values only configure issued session tokens.
    jwt_secret: str = "dev-only-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24  # 24h
    jwt_refresh_expire_days: int = 30

    # Device / encrypted AI relay routing
    device_online_ttl_seconds: int = 90
    ai_job_default_ttl_seconds: int = 300
    ai_job_max_ttl_seconds: int = 60 * 60

    # AI provider defaults. Empty model means the provider adapter must resolve
    # an explicitly configured model instead of silently guessing one.
    ollama_base_url: str = "http://127.0.0.1:11434"
    ollama_model: str = ""
    openai_compatible_base_url: str = ""

    # Paths
    project_root: Path = Path(__file__).resolve().parent.parent.parent


settings = Settings()
