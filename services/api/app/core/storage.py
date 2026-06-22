from __future__ import annotations

from minio import Minio

from app.core.config import settings

_client: Minio | None = None


def get_storage() -> Minio:
    global _client
    if _client is None:
        endpoint = settings.minio_endpoint.replace("http://", "").replace("https://", "")
        host, _, port = endpoint.partition(":")
        _client = Minio(
            f"{host}:{port or '9000'}",
            access_key=settings.minio_access_key,
            secret_key=settings.minio_secret_key,
            secure=settings.minio_endpoint.startswith("https://"),
        )
        _init_bucket(_client)
    return _client


def _init_bucket(client: Minio):
    if not client.bucket_exists(settings.minio_bucket):
        client.make_bucket(settings.minio_bucket)


def generate_upload_url(storage_key: str) -> str:
    client = get_storage()
    return client.presigned_put_object(settings.minio_bucket, storage_key)  # type: ignore[return-value]


def generate_download_url(storage_key: str) -> str:
    client = get_storage()
    return client.presigned_get_object(settings.minio_bucket, storage_key)  # type: ignore[return-value]


def check_object_exists(storage_key: str) -> bool:
    try:
        get_storage().stat_object(settings.minio_bucket, storage_key)
        return True
    except Exception:
        return False
