from __future__ import annotations

import phonenumbers


class InvalidPhoneNumber(ValueError):
    pass


def normalize_phone(phone: str, *, region: str | None = "CN") -> str:
    """Normalize a login identity to E.164 without asserting SIM ownership."""

    candidate = phone.strip()
    if not candidate:
        raise InvalidPhoneNumber("Phone number is required")
    try:
        parsed = phonenumbers.parse(candidate, region)
    except phonenumbers.NumberParseException as exc:
        raise InvalidPhoneNumber("Invalid phone number") from exc
    if not phonenumbers.is_possible_number(parsed) or not phonenumbers.is_valid_number(
        parsed
    ):
        raise InvalidPhoneNumber("Invalid phone number")
    return phonenumbers.format_number(parsed, phonenumbers.PhoneNumberFormat.E164)
