from __future__ import annotations

import io
import json
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from app.modules.imexport.csv_parser import ParsedRow, ParseResult, _detect_decode

# ─── Constants ─────────────────────────────────────────────────────────────────
_DOC_TYPES = frozenset({"doc", "clip", "journal"})
_TIME_FMTS = ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d", "%Y/%m/%d")

# ─── Frontmatter ───────────────────────────────────────────────────────────────
def _parse_frontmatter(text: str) -> tuple[dict, str]:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end == -1:
        return {}, text
    fm: dict = {}
    current_key = None
    for i in range(1, end):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        m = re.match(r"^([\w_ ]+):\s*(.*)", line)
        if m:
            current_key = m.group(1).strip()
            val = m.group(2).strip()
            if val:
                if val.startswith("[") and val.endswith("]"):
                    val = [v.strip().strip("'\"") for v in val[1:-1].split(",")]
                elif val.startswith("|"):
                    fm[current_key] = []
                    current_key = None
                    continue
                else:
                    val = val.strip("'\"")
                fm[current_key] = val
            else:
                fm[current_key] = []
        elif current_key and isinstance(fm.get(current_key), list) and stripped.startswith("- "):
            fm[current_key].append(stripped[2:].strip().strip("'\""))
    body = "\n".join(lines[end + 1:]).strip()
    return fm, body

def _fm_text(fm: dict, *keys: str) -> str | None:
    for k in keys:
        v = fm.get(k)
        if isinstance(v, list):
            return str(v[0]) if v else None
        if v is not None:
            return str(v)
    return None

def _fm_date(fm: dict, *keys: str) -> datetime | None:
    for k in keys:
        v = fm.get(k)
        if isinstance(v, str) and v.strip():
            for fmt in _TIME_FMTS:
                try:
                    return datetime.strptime(v.strip().strip("'\""), fmt).replace(tzinfo=timezone.utc)
                except ValueError:
                    continue
    return None

def _fm_tags(fm: dict, *keys: str) -> list[str]:
    tags: list[str] = []
    for k in keys:
        v = fm.get(k)
        if isinstance(v, list):
            tags.extend(str(t) for t in v)
        elif isinstance(v, str):
            tags.append(v)
    return tags

# ─── WikiLinks & inline tags ──────────────────────────────────────────────────
_WIKI_LINK_RE = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")

def _convert_wikilinks(text: str) -> str:
    def _replace(m: re.Match) -> str:
        target = m.group(1).strip()
        display = m.group(2).strip() if m.group(2) else target
        return f"[{display}]({target})"
    return _WIKI_LINK_RE.sub(_replace, text)

_TAG_RE = re.compile(r"(?:^|\s)#([\w一-鿿][\w/\-一-鿿]*)")

def _extract_inline_tags(text: str) -> list[str]:
    return [m.group(1) for m in _TAG_RE.finditer(text)]

# ─── Doc type guess ───────────────────────────────────────────────────────────
def _guess_doc_type(fm: dict, filename: str = "") -> str:
    tp = _fm_text(fm, "type", "layout")
    if tp in _DOC_TYPES:
        return tp
    stem = Path(filename).stem.lower()
    if stem in ("journal", "daily", "diary") or "日记" in stem or "daily" in stem:
        return "journal"
    if "clip" in stem:
        return "clip"
    return "doc"

# ═══════════════════════════════════════════════════════════════════════════════
#  Notion ZIP Parser
# ═══════════════════════════════════════════════════════════════════════════════
def parse_notion_markdown_zip(content: bytes) -> ParseResult:
    result = ParseResult()
    assets: list[dict] = []
    row_index = 0
    with zipfile.ZipFile(io.BytesIO(content)) as zf:
        names = zf.namelist()
        md_fpaths = sorted(n for n in names if n.endswith(".md") and not n.startswith(("_", ".")))
        attach_names = [n for n in names if n.startswith("_attachments/") and not n.endswith("/")]
        for name in attach_names:
            info = zf.getinfo(name)
            assets.append({"filename": Path(name).name, "size": info.file_size, "path": name})
        for fpath in md_fpaths:
            try:
                raw_bytes = zf.read(fpath)
                text = _detect_decode(raw_bytes)
            except Exception as exc:
                result.error_rows += 1
                result.rows.append(ParsedRow(row_index=row_index, raw_data={"file": fpath}, status="error", error=f"读取失败: {exc}"))
                row_index += 1
                continue
            fm, body = _parse_frontmatter(text)
            title = _fm_text(fm, "title") or Path(fpath).stem
            tags = _fm_tags(fm, "tags", "tag")
            created_at = _fm_date(fm, "created_at", "date", "created")
            parsed: dict = {"action": "memo_create", "type": _guess_doc_type(fm, fpath), "title": title, "content_markdown": body, "tags": tags, "source": "notion"}
            if created_at:
                parsed["created_at"] = created_at.isoformat()
            result.valid_rows += 1
            result.rows.append(ParsedRow(row_index=row_index, raw_data={"file": fpath}, parsed=parsed, status="valid"))
            row_index += 1
    for asset in assets:
        result.rows.append(ParsedRow(row_index=row_index, raw_data=asset, parsed={"action": "asset_register", "source": "notion", "filename": asset["filename"], "file_size": asset["size"]}, status="valid"))
        row_index += 1
    result.total_rows = row_index
    return result

# ═══════════════════════════════════════════════════════════════════════════════
#  Obsidian Markdown Parser
# ═══════════════════════════════════════════════════════════════════════════════
def parse_obsidian_markdown(content: bytes) -> ParseResult:
    text = _detect_decode(content)
    fm, body = _parse_frontmatter(text)
    title = _fm_text(fm, "title") or _peek_title(body) or "Untitled"
    tags_fm = _fm_tags(fm, "tags", "tag")
    created_at = _fm_date(fm, "created_at", "date", "created")
    body = _convert_wikilinks(body)
    all_tags = list(dict.fromkeys(tags_fm + _extract_inline_tags(body)))
    parsed: dict = {"action": "memo_create", "type": _guess_doc_type(fm), "title": title, "content_markdown": body, "tags": all_tags, "source": "obsidian"}
    if created_at:
        parsed["created_at"] = created_at.isoformat()
    result = ParseResult()
    result.valid_rows = 1
    result.total_rows = 1
    result.rows.append(ParsedRow(row_index=0, raw_data={"content_preview": text[:200]}, parsed=parsed, status="valid"))
    return result

def _peek_title(body: str) -> str | None:
    for line in body.split("\n"):
        m = re.match(r"^# (.+)", line.strip())
        if m:
            return m.group(1).strip()
    return None

# ═══════════════════════════════════════════════════════════════════════════════
#  飞书 Doc JSON Parser
# ═══════════════════════════════════════════════════════════════════════════════
_FEISHU_BLOCK_TYPES = frozenset({"text", "heading1", "heading2", "heading3", "bullet", "ordered", "todo", "code", "quote", "divider"})

_BLOCK_MD = {
    "text": lambda t, **_: f"{t}\n\n",
    "heading1": lambda t, **_: f"# {t}\n\n",
    "heading2": lambda t, **_: f"## {t}\n\n",
    "heading3": lambda t, **_: f"### {t}\n\n",
    "bullet": lambda t, **_: f"- {t}\n",
    "ordered": lambda t, **_: f"1. {t}\n",
    "todo": lambda t, **kw: f"- [{'x' if kw.get('done') else ' '}] {t}\n",
    "quote": lambda t, **_: f"> {t}\n\n",
    "divider": lambda **_: "---\n\n",
    "code": lambda t, **kw: f"```{kw.get('lang', '')}\n{t}\n```\n\n",
}

def _feishu_block_to_md(block: dict) -> str | None:
    btype = block.get("type", "")
    if btype not in _FEISHU_BLOCK_TYPES:
        return None
    content = block.get(btype) or block.get(f"{btype}_block") or {}
    elements = content.get("elements", []) or content.get("rich_text", [])
    text = ""
    for el in elements:
        run = el.get("text_run") or el.get("text")
        if run and isinstance(run, dict):
            text += run.get("content", "")
        link = el.get("link")
        if link and isinstance(link, dict):
            text += link.get("text", "")
    return _BLOCK_MD[btype](text, done=block.get("todo", {}).get("done"), lang=content.get("language", ""))

def _feishu_parse_table(block: dict) -> list[list[str]]:
    cells = (block.get("table") or block).get("cells", [])
    rows: list[list[str]] = []
    for cell_row in cells:
        row: list[str] = []
        for cell in cell_row:
            parts: list[str] = []
            for el in cell.get("elements", []):
                run = el.get("text_run") or el.get("text")
                if run and isinstance(run, dict):
                    parts.append(run.get("content", ""))
            row.append("".join(parts))
        if any(row):
            rows.append(row)
    if not rows:
        return []
    max_cols = max(len(r) for r in rows)
    for r in rows:
        while len(r) < max_cols:
            r.append("")
    return rows

def parse_feishu_doc_json(content: bytes) -> ParseResult:
    try:
        data = json.loads(_detect_decode(content))
    except json.JSONDecodeError as exc:
        return ParseResult(total_rows=1, error_rows=1, rows=[ParsedRow(row_index=0, raw_data={"error": str(exc)}, status="error", error=f"JSON 解析失败: {exc}")])
    blocks = data.get("blocks") or data.get("content", {}).get("blocks", []) or []
    title = data.get("title") or data.get("document_id", "Untitled")
    md_parts: list[str] = []
    csv_tables: list[list[list[str]]] = []
    for block in blocks:
        btype = block.get("type", "")
        if btype in _FEISHU_BLOCK_TYPES:
            line = _feishu_block_to_md(block)
            if line:
                md_parts.append(line)
        elif btype in ("table", "grid"):
            csv_tables.append(_feishu_parse_table(block))
    table_data = [{"table_index": ti, "row_index": ri, "cells": row} for ti, trows in enumerate(csv_tables) for ri, row in enumerate(trows)]
    parsed: dict = {"action": "memo_create", "type": "doc", "title": title, "content_markdown": "".join(md_parts).strip(), "tables": table_data, "source": "feishu"}
    return ParseResult(total_rows=1, valid_rows=1, rows=[ParsedRow(row_index=0, raw_data={"title": title, "block_count": len(blocks)}, parsed=parsed, status="valid")])
