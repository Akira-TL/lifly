from __future__ import annotations

import base64
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select

from app.core.config import settings
from app.core.storage import get_storage
from app.db.models import AccountKeyEnvelope, Asset, EncryptedEntity

EXPORT_CONTRACT_VERSION = "export.e2ee.v1"
EXPORT_ENCODING = "utf-8"
PLAINTEXT_EXPORT_WARNING = (
    "明文导出包含可直接阅读的个人数据，只能在已解密的受信设备本地生成；"
    "请自行保护导出文件。"
)
MAX_BACKUP_ASSET_BYTES = 100 * 1024 * 1024


@dataclass(frozen=True)
class ExportBoundary:
    mode: str
    execution_location: str
    contains_decrypted_user_data: bool
    available_from_cloud: bool
    privacy_warning: str
    contract_version: str = EXPORT_CONTRACT_VERSION

    def metadata(self) -> dict[str, Any]:
        return {
            "contract_version": self.contract_version,
            "mode": self.mode,
            "execution_location": self.execution_location,
            "contains_decrypted_user_data": self.contains_decrypted_user_data,
            "available_from_cloud": self.available_from_cloud,
            "privacy_warning": self.privacy_warning,
        }


@dataclass(frozen=True)
class ExportResult:
    mode: str
    media_type: str
    filename: str
    content: bytes
    counts: dict[str, int]
    checksum_sha256: str
    contract_version: str = EXPORT_CONTRACT_VERSION

    @property
    def size_bytes(self) -> int:
        return len(self.content)

    def metadata(self) -> dict[str, Any]:
        return {
            "contract_version": self.contract_version,
            "mode": self.mode,
            "execution_location": "cloud_ciphertext_only",
            "contains_decrypted_user_data": False,
            "available_from_cloud": True,
            "privacy_warning": "该备份保持端到端加密；恢复仍需要用户侧密钥材料。",
            "entity_type": "all",
            "format": "json",
            "media_type": self.media_type,
            "filename": self.filename,
            "size_bytes": self.size_bytes,
            "checksum_sha256": self.checksum_sha256,
            "counts": self.counts,
            "preview": "",
        }


def plaintext_export_boundary() -> ExportBoundary:
    return ExportBoundary(
        mode="plaintext",
        execution_location="trusted_client",
        contains_decrypted_user_data=True,
        available_from_cloud=False,
        privacy_warning=PLAINTEXT_EXPORT_WARNING,
    )


async def build_encrypted_backup_result(
    db,
    *,
    user_id: str,
    include_asset_ciphertext: bool = True,
) -> ExportResult:
    entity_result = await db.execute(
        select(EncryptedEntity)
        .where(EncryptedEntity.user_id == user_id)
        .order_by(EncryptedEntity.updated_at.asc())
    )
    entities = entity_result.scalars().all()

    key_result = await db.execute(
        select(AccountKeyEnvelope)
        .where(AccountKeyEnvelope.account_id == user_id)
        .order_by(AccountKeyEnvelope.key_version.asc())
    )
    key_envelopes = key_result.scalars().all()

    asset_result = await db.execute(
        select(Asset)
        .where(
            Asset.user_id == user_id,
            Asset.kind == "internal",
            Asset.status != "purged",
        )
        .order_by(Asset.created_at.asc())
    )
    assets = asset_result.scalars().all()

    asset_objects: list[dict[str, Any]] = []
    for asset in assets:
        item: dict[str, Any] = {
            "asset_id": asset.id,
            "storage_key": asset.storage_key,
            "ciphertext_size_bytes": asset.size_bytes,
            "ciphertext_sha256": asset.sha256,
            "status": asset.status,
        }
        if include_asset_ciphertext and asset.storage_key:
            ciphertext = _read_asset_ciphertext(asset.storage_key)
            item["ciphertext_base64"] = base64.b64encode(ciphertext).decode("ascii")
        asset_objects.append(item)

    payload = {
        "contract_version": EXPORT_CONTRACT_VERSION,
        "mode": "encrypted_backup",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "account_id": user_id,
        "encrypted_entities": [_encrypted_entity_dict(item) for item in entities],
        "account_key_envelopes": [_key_envelope_dict(item) for item in key_envelopes],
        "encrypted_asset_objects": asset_objects,
    }
    content = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode(
        EXPORT_ENCODING
    )
    counts = {
        "encrypted_entities": len(entities),
        "account_key_envelopes": len(key_envelopes),
        "encrypted_asset_objects": len(asset_objects),
    }
    return ExportResult(
        mode="encrypted_backup",
        media_type="application/json",
        filename="lifly-encrypted-backup.json",
        content=content,
        counts=counts,
        checksum_sha256=hashlib.sha256(content).hexdigest(),
    )


def _encrypted_entity_dict(entity: EncryptedEntity) -> dict[str, Any]:
    return {
        "id": entity.id,
        "user_id": entity.user_id,
        "entity_type": entity.entity_type,
        "revision": entity.revision,
        "lifecycle_status": entity.lifecycle_status,
        "updated_at": entity.updated_at.isoformat(),
        "key_version": entity.key_version,
        "encryption_version": entity.encryption_version,
        "schema_version": entity.schema_version,
        "nonce": entity.nonce,
        "ciphertext": entity.ciphertext,
    }


def _key_envelope_dict(envelope: AccountKeyEnvelope) -> dict[str, Any]:
    return {
        "account_id": envelope.account_id,
        "envelope_type": envelope.envelope_type,
        "key_version": envelope.key_version,
        "encryption_version": envelope.encryption_version,
        "schema_version": envelope.schema_version,
        "nonce": envelope.nonce,
        "ciphertext": envelope.ciphertext,
    }


def _read_asset_ciphertext(storage_key: str) -> bytes:
    response = get_storage().get_object(settings.minio_bucket, storage_key)
    try:
        payload = response.read(MAX_BACKUP_ASSET_BYTES + 1)
    finally:
        response.close()
        response.release_conn()
    if len(payload) > MAX_BACKUP_ASSET_BYTES:
        raise ValueError(
            f"Encrypted asset exceeds backup limit of {MAX_BACKUP_ASSET_BYTES} bytes"
        )
    return payload
