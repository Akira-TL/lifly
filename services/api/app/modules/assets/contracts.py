from __future__ import annotations

from pydantic import BaseModel, Field, field_validator


class EncryptedAssetReserveRequest(BaseModel):
    asset_id: str | None = Field(default=None, min_length=1, max_length=128)


class EncryptedAssetUploadCompleteRequest(BaseModel):
    ciphertext_sha256: str = Field(min_length=64, max_length=64)
    ciphertext_size_bytes: int = Field(gt=0)

    @field_validator("ciphertext_sha256")
    @classmethod
    def validate_sha256(cls, value: str) -> str:
        normalized = value.strip().lower()
        if len(normalized) != 64 or any(char not in "0123456789abcdef" for char in normalized):
            raise ValueError("ciphertext_sha256 must be 64 lowercase hex characters")
        return normalized
