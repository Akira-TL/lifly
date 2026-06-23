"""
ICS (RFC 5545 日历格式) 导入/导出处理器。
"""
from __future__ import annotations

import re
from datetime import datetime, timezone
from typing import Any

from app.modules.imexport.csv_parser import ParsedRow, ParseResult


def parse_ics(content: bytes) -> ParseResult:
    """解析 ICS 文件内容，返回 ParseResult。每个 VEVENT 转为一条 calendar_event 记录。"""
    text = content.decode("utf-8", errors="replace")
    result = ParseResult()

    unfolded = _unfold_lines(text)
    blocks = _extract_blocks(unfolded, "VEVENT")

    for idx, block in enumerate(blocks):
        raw_data = {k: v for k, v in block}
        parsed, error = _parse_vevent(block)
        status = "error" if error else "valid"
        if status == "valid":
            result.valid_rows += 1
        else:
            result.error_rows += 1
        result.total_rows += 1
        result.rows.append(ParsedRow(
            row_index=idx,
            raw_data=raw_data,
            parsed=parsed,
            status=status,
            error=error,
        ))

    return result


def export_ics(events: list[dict]) -> bytes:
    """将日历事件列表导出为 ICS 格式（RFC 5545）。"""
    lines: list[str] = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Lifily//Calendar//CN",
    ]

    for event in events:
        lines.append("BEGIN:VEVENT")
        lines.append(f"SUMMARY:{_escape_text(event.get('title') or '')}")

        desc = event.get("description")
        if desc:
            lines.append(f"DESCRIPTION:{_escape_text(desc)}")

        location = event.get("location")
        if location:
            lines.append(f"LOCATION:{_escape_text(location)}")

        is_all_day = event.get("is_all_day", False)
        start_dt = _format_dt(event.get("start_at"), is_all_day)
        if start_dt:
            lines.append(f"DTSTART{start_dt}")
        end_dt = _format_dt(event.get("end_at"), is_all_day)
        if end_dt:
            lines.append(f"DTEND{end_dt}")

        rrule = event.get("rrule")
        if rrule:
            lines.append(f"RRULE:{rrule}")

        lines.append("END:VEVENT")

    lines.append("END:VCALENDAR")

    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


# ─── ICS 解析辅助函数 ──────────────────────────────────────────────────────────


def _unfold_lines(text: str) -> list[str]:
    """展开 ICS 折行（RFC 5545 5.8.1）。"""
    unfolded: list[str] = []
    for line in text.splitlines():
        if line and line[0] in (" ", "\t") and unfolded:
            unfolded[-1] += line[1:]
        else:
            unfolded.append(line)
    return unfolded


def _extract_blocks(lines: list[str], component: str) -> list[list[tuple[str, str]]]:
    """提取指定类型的组件块，每个块返回 [(full_key, value), ...]。"""
    blocks: list[list[tuple[str, str]]] = []
    current: list[tuple[str, str]] | None = None
    begin_tag = f"BEGIN:{component}"
    end_tag = f"END:{component}"
    for line in lines:
        upper = line.upper().strip()
        if upper.startswith(begin_tag):
            current = []
        elif upper.startswith(end_tag) and current is not None:
            blocks.append(current)
            current = None
        elif current is not None and ":" in line:
            key, _, value = line.partition(":")
            current.append((key, value))
    return blocks


def _parse_params(key: str) -> tuple[str, dict[str, str]]:
    """从完整 key 中分离属性名和参数（如 TZID、VALUE）。"""
    parts = key.split(";")
    prop_name = parts[0].upper()
    params: dict[str, str] = {}
    for p in parts[1:]:
        if "=" in p:
            k, _, v = p.partition("=")
            params[k.upper()] = v
    return prop_name, params


def _parse_dt(value: str, params: dict[str, str]) -> tuple[datetime | None, bool]:
    """解析日期时间值，返回 (datetime_utc, is_all_day)。"""
    value = value.strip()

    if params.get("VALUE") == "DATE":
        try:
            dt = datetime.strptime(value, "%Y%m%d")
            return dt.replace(tzinfo=timezone.utc), True
        except ValueError:
            return None, False

    if value.endswith("Z"):
        try:
            dt = datetime.strptime(value[:-1], "%Y%m%dT%H%M%S")
            return dt.replace(tzinfo=timezone.utc), False
        except ValueError:
            return None, False

    if len(value) == 8 and value.isdigit():
        try:
            dt = datetime.strptime(value, "%Y%m%d")
            return dt.replace(tzinfo=timezone.utc), True
        except ValueError:
            return None, False

    try:
        dt = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
        return dt.replace(tzinfo=timezone.utc), False
    except (ValueError, IndexError):
        return None, False


_ESCAPE_RE = re.compile(r"\\([Nn;,\\])")


def _unescape_text(value: str) -> str:
    """反转义 ICS 文本值。"""
    def _replace(m: re.Match) -> str:
        ch = m.group(1)
        return {"n": "\n", "N": "\n", ";": ";", ",": ",", "\\": "\\"}.get(ch, ch)
    return _ESCAPE_RE.sub(_replace, value)


def _parse_vevent(block: list[tuple[str, str]]) -> tuple[dict[str, Any] | None, str | None]:
    """解析一个 VEVENT 块，返回 (parsed_dict, error_message)。"""
    summary = ""
    description = ""
    location = ""
    rrule = ""
    start_at: datetime | None = None
    end_at: datetime | None = None
    is_all_day = False

    for key, value in block:
        prop_name, params = _parse_params(key)
        if prop_name == "SUMMARY":
            summary = _unescape_text(value)
        elif prop_name == "DESCRIPTION":
            description = _unescape_text(value)
        elif prop_name == "LOCATION":
            location = _unescape_text(value)
        elif prop_name == "RRULE":
            rrule = value.strip()
        elif prop_name == "DTSTART":
            start_at, is_all_day = _parse_dt(value, params)
        elif prop_name == "DTEND":
            end_at, _ = _parse_dt(value, params)

    if start_at is None:
        return None, "缺少 DTSTART 或无法解析"

    parsed: dict[str, Any] = {
        "type": "calendar_event",
        "title": summary or "无标题",
        "description": description or None,
        "start_at": start_at.isoformat(),
        "end_at": end_at.isoformat() if end_at else None,
        "location": location or None,
        "rrule": rrule or None,
        "is_all_day": is_all_day,
    }
    return parsed, None


# ─── ICS 导出辅助函数 ──────────────────────────────────────────────────────────


def _escape_text(value: str) -> str:
    """转义 ICS 文本值（RFC 5545 3.3.11）。"""
    value = value.replace("\\", "\\\\")
    value = value.replace(";", "\\;")
    value = value.replace(",", "\\,")
    value = value.replace("\n", "\\n")
    return value


def _format_dt(dt_str: str | None, is_all_day: bool = False) -> str | None:
    """将 ISO 格式日期时间转为 ICS 格式。"""
    if dt_str is None:
        return None
    try:
        dt = datetime.fromisoformat(dt_str)
    except (ValueError, TypeError):
        return None
    if is_all_day:
        return f";VALUE=DATE:{dt.strftime('%Y%m%d')}"
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    else:
        dt = dt.astimezone(timezone.utc)
    return f":{dt.strftime('%Y%m%dT%H%M%S')}Z"
