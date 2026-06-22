from __future__ import annotations

import csv
import hashlib
import io
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone


@dataclass
class ParsedRow:
    row_index: int
    raw_data: dict[str, str]
    parsed: dict | None = None
    status: str = "pending"  # pending / valid / duplicate / error
    error: str | None = None


@dataclass
class ParseResult:
    rows: list[ParsedRow] = field(default_factory=list)
    total_rows: int = 0
    valid_rows: int = 0
    duplicate_rows: int = 0
    error_rows: int = 0


# ─── 通用 CSV ─────────────────────────────────────────────────────────────────

def parse_generic_csv(content: bytes, user_id: str) -> ParseResult:
    """解析通用账单 CSV。"""
    text = _detect_decode(content)
    reader = csv.DictReader(io.StringIO(text))
    return _normalize_rows(reader, "generic")


# ─── 支付宝 CSV ───────────────────────────────────────────────────────────────

ALIPAY_DATE_RE = re.compile(r"(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})")
ALIPAY_AMOUNT_RE = re.compile(r"[-]?\d+(?:\.\d{1,2})?")


def parse_alipay_csv(content: bytes, user_id: str) -> ParseResult:
    """解析支付宝账单 CSV。"""
    text = _detect_decode(content)
    reader = csv.DictReader(io.StringIO(text))
    result = ParseResult()

    for i, row in enumerate(reader):
        raw = dict(row)
        result.total_rows += 1
        parsed = {}

        # 常见的支付宝列名映射
        date_str = _get(row, ["交易时间", "交易日期", "time", "date", "创建时间"])
        direction = "expense"
        amount_str = _get(row, ["金额", "交易金额", "amount", "收入金额", "支出金额"])
        merchant = _get(row, ["交易对方", "商户名称", "merchant", "对方", "商品名称"])
        note = _get(row, ["商品说明", "备注", "note", "description", "商品描述"])
        category = _get(row, ["交易分类", "category", "类型"])

        # 收支判断
        income_str = _get(row, ["收入金额", "收/支"])
        expense_str = _get(row, ["支出金额", "支出"])
        if income_str:
            income_val = _safe_float(income_str)
            if income_val and income_val > 0:
                direction = "income"
                amount_str = income_str
        elif expense_str and _safe_float(expense_str):
            direction = "expense"
            amount_str = expense_str
        elif "收入" in str(_get(row, ["收/支", "资金流向"])) or _get(row, ["收/支"]) == "收入":
            direction = "income"

        amount = _safe_float(amount_str) if amount_str else None
        occurred_at = _parse_date(date_str) if date_str else datetime.now(timezone.utc)

        if amount is None or amount <= 0:
            parsed_status = "error"
            result.error_rows += 1
            error = "无法解析金额"
        elif occurred_at is None:
            parsed_status = "error"
            result.error_rows += 1
            error = "无法解析日期"
        else:
            parsed_status = "valid"
            result.valid_rows += 1
            error = None

        parsed = {
            "direction": direction,
            "amount": amount,
            "currency": "CNY",
            "merchant": merchant or "未知",
            "note": note,
            "category_hint": category,
            "occurred_at": occurred_at.isoformat() if occurred_at else None,
        }

        result.rows.append(ParsedRow(
            row_index=i,
            raw_data=raw,
            parsed=parsed,
            status=parsed_status,
            error=error,
        ))

    return result


# ─── 微信支付 CSV ─────────────────────────────────────────────────────────────

def parse_wechat_csv(content: bytes, user_id: str) -> ParseResult:
    """解析微信支付账单 CSV。"""
    text = _detect_decode(content)
    reader = csv.DictReader(io.StringIO(text))
    result = ParseResult()

    for i, row in enumerate(reader):
        raw = dict(row)
        result.total_rows += 1

        # 微信账单常见列名
        date_str = _get(row, ["交易时间", "time", "date"])
        merchant = _get(row, ["交易对方", "商户名称", "merchant", "对方"])
        note = _get(row, ["商品", "交易类型", "商品名称", "备注", "note"])
        direction_str = _get(row, ["收/支", "交易类型", "收支类型", "type"])
        amount_str = _get(row, ["金额(元)", "金额", "amount"])

        direction = "expense"
        if direction_str and "收入" in direction_str:
            direction = "income"

        amount = _safe_float(amount_str) if amount_str else None
        occurred_at = _parse_date(date_str) if date_str else datetime.now(timezone.utc)

        if amount is None or amount <= 0:
            parsed_status = "error"
            result.error_rows += 1
            error = "无法解析金额"
        elif occurred_at is None:
            parsed_status = "error"
            result.error_rows += 1
            error = "无法解析日期"
        else:
            parsed_status = "valid"
            result.valid_rows += 1
            error = None

        parsed = {
            "direction": direction,
            "amount": amount,
            "currency": "CNY",
            "merchant": merchant or "未知",
            "note": note,
            "occurred_at": occurred_at.isoformat() if occurred_at else None,
        }

        result.rows.append(ParsedRow(
            row_index=i,
            raw_data=raw,
            parsed=parsed,
            status=parsed_status,
            error=error,
        ))

    return result


# ─── Helpers ──────────────────────────────────────────────────────────────────

PARSERS = {
    "alipay": parse_alipay_csv,
    "wechat": parse_wechat_csv,
    "generic": parse_generic_csv,
}


def _normalize_rows(reader: csv.DictReader, provider: str) -> ParseResult:
    result = ParseResult()
    for i, row in enumerate(reader):
        raw = dict(row)
        result.total_rows += 1

        direction = _get(row, ["direction", "收支方向", "收/支"]) or "expense"
        if "income" in direction.lower() or "收入" in direction:
            direction = "income"
        else:
            direction = "expense"

        amount_str = _get(row, ["amount", "金额"])
        amount = _safe_float(amount_str) if amount_str else None
        merchant = _get(row, ["merchant", "商户", "交易对方", "merchant_name"])
        note = _get(row, ["note", "备注", "商品说明"])
        category = _get(row, ["category", "分类", "交易分类"])
        date_str = _get(row, ["occurred_at", "交易时间", "日期", "date", "time"])
        occurred_at = _parse_date(date_str) if date_str else datetime.now(timezone.utc)

        if amount is None or amount <= 0:
            result.error_rows += 1
            status = "error"
            error = "无法解析金额"
        elif occurred_at is None:
            result.error_rows += 1
            status = "error"
            error = "无法解析日期"
        else:
            result.valid_rows += 1
            status = "valid"
            error = None

        result.rows.append(ParsedRow(
            row_index=i,
            raw_data=raw,
            parsed={
                "direction": direction,
                "amount": amount,
                "currency": _get(row, ["currency", "货币"]) or "CNY",
                "merchant": merchant or "未知",
                "note": note,
                "category_hint": category,
                "occurred_at": occurred_at.isoformat() if occurred_at else None,
            },
            status=status,
            error=error,
        ))
    return result


def _get(row: dict, keys: list[str]) -> str | None:
    for k in keys:
        if k in row and row[k]:
            return str(row[k]).strip()
    # 大小写不敏感
    for k in keys:
        kl = k.lower()
        for rk in row:
            if rk.lower() == kl and row[rk]:
                return str(row[rk]).strip()
    return None


def _safe_float(val: str | None) -> float | None:
    if not val:
        return None
    val = str(val).replace(",", "").replace("¥", "").replace("￥", "").replace("元", "").strip()
    if val.startswith("-"):
        val = val[1:]
    try:
        return float(val)
    except ValueError:
        return None


def _parse_date(val: str) -> datetime | None:
    if not val:
        return None
    formats = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d",
        "%Y/%m/%d",
    ]
    for fmt in formats:
        try:
            dt = datetime.strptime(val.strip(), fmt)
            return dt.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def _detect_decode(content: bytes) -> str:
    for enc in ["utf-8", "utf-8-sig", "gbk", "gb2312", "gb18030"]:
        try:
            return content.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return content.decode("utf-8", errors="replace")


def compute_file_hash(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()
