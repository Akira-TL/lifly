from __future__ import annotations

import csv
import hashlib
import io
import re
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from xml.etree import ElementTree as ET


@dataclass
class ParsedRow:
    row_index: int
    raw_data: dict[str, str]
    parsed: dict | None = None
    status: str = "pending"  # pending / valid / duplicate / error / ignored
    error: str | None = None


@dataclass
class ParseResult:
    rows: list[ParsedRow] = field(default_factory=list)
    total_rows: int = 0
    valid_rows: int = 0
    duplicate_rows: int = 0
    error_rows: int = 0
    ignored_rows: int = 0
    provider: str = "generic"


# ─── Provider entrypoints ─────────────────────────────────────────────────────

def parse_auto_statement(content: bytes, user_id: str) -> ParseResult:
    provider = detect_statement_provider(content)
    parser = PARSERS[provider]
    return parser(content, user_id)


def parse_generic_csv(content: bytes, user_id: str) -> ParseResult:
    rows = _read_tabular_rows(content)
    header_index = _find_header_row(rows, ["amount", "金额", "交易时间", "记录时间"])
    result = _normalize_rows(_rows_to_dicts(rows, header_index), "generic")
    result.provider = "generic"
    return result


# ─── 支付宝 / 记账本 CSV ──────────────────────────────────────────────────────

ALIPAY_PROVIDER = "alipay"
WECHAT_PROVIDER = "wechat"
GENERIC_PROVIDER = "generic"


def parse_alipay_csv(content: bytes, user_id: str) -> ParseResult:
    """解析支付宝账单 / 支付宝记账本 CSV。"""
    rows = _read_tabular_rows(content)
    header_index = _find_header_row(rows, [
        "记录时间",
        "交易时间",
        "交易日期",
        "收支类型",
        "收入金额",
        "支出金额",
        "金额",
    ])
    result = ParseResult(provider=ALIPAY_PROVIDER)

    for i, row in enumerate(_rows_to_dicts(rows, header_index)):
        raw = dict(row)
        result.total_rows += 1

        date_str = _get(row, ["记录时间", "交易时间", "交易日期", "time", "date", "创建时间"])
        direction_text = _get(row, ["收支类型", "收/支", "资金流向", "交易类型", "类型"])
        amount_str = _get(row, ["金额", "交易金额", "amount", "收入金额", "支出金额"])
        merchant = _get(row, ["交易对方", "商户名称", "merchant", "对方", "商品名称", "备注"])
        note = _get(row, ["备注", "商品说明", "note", "description", "商品描述", "来源"])
        category = _get(row, ["分类", "交易分类", "category", "类型"])
        account = _get(row, ["账户", "支付方式", "付款方式"])
        source = _get(row, ["来源", "source"])

        direction = _normalize_direction(direction_text)
        income_str = _get(row, ["收入金额"])
        expense_str = _get(row, ["支出金额"])
        if _safe_float(income_str) and (_safe_float(income_str) or 0) > 0:
            direction = "income"
            amount_str = income_str
        elif _safe_float(expense_str) and (_safe_float(expense_str) or 0) > 0:
            direction = "expense"
            amount_str = expense_str

        parsed, status, error = _build_ledger_preview(
            row,
            provider=ALIPAY_PROVIDER,
            direction=direction,
            amount_str=amount_str,
            occurred_at_str=date_str,
            merchant=merchant,
            note=note,
            category=category,
            account=account,
            source=source,
            external_id=_get(row, ["交易号", "商户订单号", "订单号", "账单流水号"]),
        )
        _append_result(result, row_index=i, raw=raw, parsed=parsed, status=status, error=error)

    return result


# ─── 微信支付 XLSX / CSV ──────────────────────────────────────────────────────

def parse_wechat_csv(content: bytes, user_id: str) -> ParseResult:
    """解析微信支付 XLSX / CSV 账单。"""
    rows = _read_tabular_rows(content)
    header_index = _find_header_row(rows, ["交易时间", "交易类型", "交易对方", "收/支", "金额(元)"])
    result = ParseResult(provider=WECHAT_PROVIDER)

    for i, row in enumerate(_rows_to_dicts(rows, header_index)):
        raw = dict(row)
        result.total_rows += 1

        direction_text = _get(row, ["收/支", "交易类型", "收支类型", "type"])
        direction = _normalize_direction(direction_text)
        parsed, status, error = _build_ledger_preview(
            row,
            provider=WECHAT_PROVIDER,
            direction=direction,
            amount_str=_get(row, ["金额(元)", "金额", "amount"]),
            occurred_at_str=_get(row, ["交易时间", "time", "date"]),
            merchant=_get(row, ["交易对方", "商户名称", "merchant", "对方"]),
            note=_join_non_empty([
                _get(row, ["商品", "商品名称"]),
                _get(row, ["备注", "note"]),
            ]),
            category=_get(row, ["交易类型"]),
            account=_get(row, ["支付方式"]),
            source=_get(row, ["当前状态"]),
            external_id=_get(row, ["交易单号", "商户单号"]),
        )
        _append_result(result, row_index=i, raw=raw, parsed=parsed, status=status, error=error)

    return result


# ─── Detection ────────────────────────────────────────────────────────────────

def detect_statement_provider(content: bytes) -> str:
    if _is_xlsx(content):
        rows = _read_xlsx_rows(content, max_rows=30)
        flattened = "\n".join("\t".join(row) for row in rows)
        if "微信支付账单" in flattened or _has_header(rows, ["交易时间", "交易对方", "金额(元)"]):
            return WECHAT_PROVIDER
        return GENERIC_PROVIDER

    text = _detect_decode(content)
    preview = text[:8000]
    if "支付宝" in preview or "记录时间,分类,收支类型,金额" in preview:
        return ALIPAY_PROVIDER
    if "微信支付账单" in preview or "金额(元)" in preview:
        return WECHAT_PROVIDER
    return GENERIC_PROVIDER


# ─── Normalization ────────────────────────────────────────────────────────────

def _normalize_rows(rows: list[dict[str, str]], provider: str) -> ParseResult:
    result = ParseResult(provider=provider)
    for i, row in enumerate(rows):
        raw = dict(row)
        result.total_rows += 1
        direction = _normalize_direction(_get(row, ["direction", "收支方向", "收/支", "收支类型"]))
        parsed, status, error = _build_ledger_preview(
            row,
            provider=provider,
            direction=direction,
            amount_str=_get(row, ["amount", "金额", "金额(元)"]),
            occurred_at_str=_get(row, ["occurred_at", "交易时间", "记录时间", "日期", "date", "time"]),
            merchant=_get(row, ["merchant", "商户", "交易对方", "merchant_name", "备注"]),
            note=_get(row, ["note", "备注", "商品说明", "商品"]),
            category=_get(row, ["category", "分类", "交易分类", "交易类型"]),
            account=_get(row, ["account", "账户", "支付方式"]),
            source=_get(row, ["source", "来源"]),
            external_id=_get(row, ["external_id", "交易单号", "交易号", "商户单号"]),
        )
        _append_result(result, row_index=i, raw=raw, parsed=parsed, status=status, error=error)
    return result


def _build_ledger_preview(
    row: dict[str, str],
    *,
    provider: str,
    direction: str,
    amount_str: str | None,
    occurred_at_str: str | None,
    merchant: str | None,
    note: str | None,
    category: str | None,
    account: str | None,
    source: str | None,
    external_id: str | None,
) -> tuple[dict, str, str | None]:
    amount = _safe_float(amount_str)
    occurred_at = _parse_date(occurred_at_str) if occurred_at_str else None

    status = "valid"
    error = None
    if direction == "transfer":
        status = "ignored"
        error = "中性/不计收支交易暂不导入"
    elif amount is None or amount <= 0:
        status = "error"
        error = "无法解析金额"
    elif occurred_at is None:
        status = "error"
        error = "无法解析日期"

    parsed = {
        "direction": direction,
        "amount": amount,
        "currency": _get(row, ["currency", "货币", "币种"]) or "CNY",
        "merchant": merchant or "未知",
        "note": note,
        "category_hint": category,
        "account_hint": account,
        "source_provider": provider,
        "source_status": source,
        "external_id": external_id,
        "occurred_at": occurred_at.isoformat() if occurred_at else None,
    }
    return parsed, status, error


def _append_result(
    result: ParseResult,
    *,
    row_index: int,
    raw: dict[str, str],
    parsed: dict,
    status: str,
    error: str | None,
) -> None:
    if status == "valid":
        result.valid_rows += 1
    elif status == "ignored":
        result.ignored_rows += 1
    elif status == "duplicate":
        result.duplicate_rows += 1
    elif status == "error":
        result.error_rows += 1

    result.rows.append(ParsedRow(
        row_index=row_index,
        raw_data=raw,
        parsed=parsed if status in {"valid", "ignored"} else None,
        status=status,
        error=error,
    ))


# ─── Tabular readers ──────────────────────────────────────────────────────────

def _read_tabular_rows(content: bytes) -> list[list[str]]:
    if _is_xlsx(content):
        return _read_xlsx_rows(content)
    text = _detect_decode(content)
    reader = csv.reader(io.StringIO(text))
    return [[_clean_cell(cell) for cell in row] for row in reader]


def _rows_to_dicts(rows: list[list[str]], header_index: int) -> list[dict[str, str]]:
    if header_index < 0 or header_index >= len(rows):
        return []
    headers = [_clean_header(cell) for cell in rows[header_index]]
    dict_rows: list[dict[str, str]] = []
    for row in rows[header_index + 1:]:
        if not any(cell.strip() for cell in row):
            continue
        item: dict[str, str] = {}
        for idx, header in enumerate(headers):
            if not header:
                continue
            item[header] = _clean_cell(row[idx]) if idx < len(row) else ""
        if any(item.values()):
            dict_rows.append(item)
    return dict_rows


def _find_header_row(rows: list[list[str]], required_tokens: list[str]) -> int:
    best_index = -1
    best_score = 0
    tokens = [token.lower() for token in required_tokens]
    for idx, row in enumerate(rows[:80]):
        normalized = [_clean_header(cell).lower() for cell in row]
        joined = "\t".join(normalized)
        score = sum(1 for token in tokens if token.lower() in normalized or token.lower() in joined)
        if score > best_score:
            best_score = score
            best_index = idx
    if best_index >= 0 and best_score >= 2:
        return best_index
    if rows:
        return 0
    return -1


def _has_header(rows: list[list[str]], headers: list[str]) -> bool:
    header_set = set(headers)
    for row in rows[:80]:
        values = set(_clean_header(cell) for cell in row)
        if len(header_set & values) >= min(2, len(header_set)):
            return True
    return False


def _is_xlsx(content: bytes) -> bool:
    return content[:4] == b"PK\x03\x04"


def _read_xlsx_rows(content: bytes, *, max_rows: int | None = None) -> list[list[str]]:
    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        shared_strings = _read_shared_strings(zf)
        worksheet_name = _first_worksheet_name(zf)
        xml = zf.read(worksheet_name)

    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    root = ET.fromstring(xml)
    rows: list[list[str]] = []
    for row_el in root.findall(".//x:sheetData/x:row", ns):
        values_by_col: dict[int, str] = {}
        for cell_el in row_el.findall("x:c", ns):
            ref = cell_el.attrib.get("r", "A1")
            col_idx = _column_index(ref)
            values_by_col[col_idx] = _cell_value(cell_el, shared_strings, ns)
        if values_by_col:
            max_col = max(values_by_col)
            rows.append([values_by_col.get(i, "") for i in range(max_col + 1)])
        else:
            rows.append([])
        if max_rows is not None and len(rows) >= max_rows:
            break
    return rows


def _read_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    try:
        xml = zf.read("xl/sharedStrings.xml")
    except KeyError:
        return []
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    root = ET.fromstring(xml)
    values: list[str] = []
    for si in root.findall("x:si", ns):
        parts = [node.text or "" for node in si.findall(".//x:t", ns)]
        values.append("".join(parts))
    return values


def _first_worksheet_name(zf: zipfile.ZipFile) -> str:
    candidates = sorted(
        name for name in zf.namelist()
        if name.startswith("xl/worksheets/sheet") and name.endswith(".xml")
    )
    if not candidates:
        raise ValueError("xlsx file does not contain worksheets")
    return candidates[0]


def _cell_value(cell_el: ET.Element, shared_strings: list[str], ns: dict[str, str]) -> str:
    cell_type = cell_el.attrib.get("t")
    if cell_type == "inlineStr":
        texts = [node.text or "" for node in cell_el.findall(".//x:t", ns)]
        return _clean_cell("".join(texts))

    value_el = cell_el.find("x:v", ns)
    if value_el is None or value_el.text is None:
        return ""
    value = value_el.text
    if cell_type == "s":
        try:
            return _clean_cell(shared_strings[int(value)])
        except (ValueError, IndexError):
            return ""
    return _clean_cell(value)


def _column_index(ref: str) -> int:
    letters = "".join(ch for ch in ref if ch.isalpha()).upper()
    index = 0
    for ch in letters:
        index = index * 26 + (ord(ch) - ord("A") + 1)
    return max(index - 1, 0)


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _get(row: dict, keys: list[str]) -> str | None:
    for key in keys:
        if key in row and row[key]:
            return _clean_cell(row[key])
    for key in keys:
        key_norm = _normalize_key(key)
        for row_key, value in row.items():
            if _normalize_key(row_key) == key_norm and value:
                return _clean_cell(value)
    return None


def _normalize_key(value: str) -> str:
    return re.sub(r"\s+", "", value).lower()


def _clean_header(value: str | None) -> str:
    return _clean_cell(value).strip(" ,，")


def _clean_cell(value: object | None) -> str:
    if value is None:
        return ""
    return str(value).strip().replace("\ufeff", "")


def _join_non_empty(values: list[str | None]) -> str | None:
    items = [value for value in values if value and value != "/"]
    return " | ".join(items) if items else None


def _normalize_direction(value: str | None) -> str:
    text = (value or "").strip().lower()
    if not text:
        return "expense"
    if text in {"/", "-", "—"}:
        return "transfer"
    if any(token in text for token in ["收入", "收款", "income", "in"]):
        return "income"
    if any(token in text for token in ["中性", "不计收支", "转账", "提现", "充值", "信用卡还款", "零钱通", "理财通"]):
        return "transfer"
    return "expense"


def _safe_float(value: str | None) -> float | None:
    if not value:
        return None
    normalized = str(value)
    normalized = normalized.replace(",", "").replace("¥", "").replace("￥", "")
    normalized = normalized.replace("元", "").replace("+", "").strip()
    match = re.search(r"-?\d+(?:\.\d+)?", normalized)
    if not match:
        return None
    try:
        return abs(float(match.group(0)))
    except ValueError:
        return None


def _parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    text = _clean_cell(value)
    excel_date = _parse_excel_serial_date(text)
    if excel_date is not None:
        return excel_date
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
            dt = datetime.strptime(text, fmt)
            return dt.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    return None


def _parse_excel_serial_date(value: str) -> datetime | None:
    try:
        serial = float(value)
    except ValueError:
        return None
    if serial < 20000 or serial > 80000:
        return None
    base = datetime(1899, 12, 30, tzinfo=timezone.utc)
    return base + timedelta(days=serial)


def _detect_decode(content: bytes) -> str:
    for enc in ["utf-8-sig", "utf-8", "gb18030", "gbk", "gb2312"]:
        try:
            return content.decode(enc)
        except (UnicodeDecodeError, LookupError):
            continue
    return content.decode("utf-8", errors="replace")


def compute_file_hash(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


PARSERS = {
    "auto": parse_auto_statement,
    ALIPAY_PROVIDER: parse_alipay_csv,
    WECHAT_PROVIDER: parse_wechat_csv,
    GENERIC_PROVIDER: parse_generic_csv,
}
