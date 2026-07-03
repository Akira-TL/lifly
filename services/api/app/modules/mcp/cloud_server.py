from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

import httpx
from mcp.server.fastmcp import FastMCP
from mcp.types import Tool, TextContent

from app.core.config import settings
from app.core.security import create_access_token

cloud_mcp = FastMCP(
    "lifly-cloud",
    instructions="Lifly Cloud MCP — AI 接入边界。捕获自然语言输入、管理备忘/账单/任务、上传附件。",
    stateless_http=True,
    json_response=True,
    streamable_http_path="/mcp",
)


# ─── capture_parse ───────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="capture_parse",
    description="解析自然语言为候选动作（备忘/账单/任务），不正式写入。返回 capture_id 用于确认或撤销。",
)
async def capture_parse(
    text: str,
    timezone: str = "Asia/Shanghai",
    locale: str = "zh-CN",
) -> str:
    resp = await _call_internal("/api/v1/mcp/capture/parse", body={
        "text": text,
        "timezone": timezone,
        "locale": locale,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── capture_commit ──────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="capture_commit",
    description="确认执行 capture_parse 产生的全部或部分动作，写入数据库。返回 undo_token。",
)
async def capture_commit(
    capture_id: str,
    selected_action_indexes: list[int] | None = None,
) -> str:
    resp = await _call_internal("/api/v1/mcp/capture/commit", body={
        "capture_id": capture_id,
        "selected_action_indexes": selected_action_indexes,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── capture_undo ────────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="capture_undo",
    description="撤销上一次 capture_commit 操作，将实体移入 AI 回收站。",
)
async def capture_undo(undo_token: str) -> str:
    resp = await _call_internal("/api/v1/mcp/capture/undo", body={
        "undo_token": undo_token,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── memo_create ─────────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="memo_create",
    description="创建备忘录，支持 markdown 内容和标签。",
)
async def memo_create(
    content_markdown: str,
    title: str | None = None,
    type: str = "memo",
    tags: list[str] | None = None,
) -> str:
    resp = await _call_internal("/api/v1/mcp/memo/create", body={
        "type": type,
        "title": title,
        "content_markdown": content_markdown,
        "tags": tags,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── memo_search ─────────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="memo_search",
    description="搜索备忘内容（标题 + 正文模糊匹配）。",
)
async def memo_search(q: str = "", limit: int = 20) -> str:
    resp = await _call_internal("/api/v1/mcp/memo/search", body={
        "q": q,
        "limit": limit,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── expense_create ──────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="expense_create",
    description="创建账单记录，支持金额/方向/商户/分类。",
)
async def expense_create(
    amount: float,
    merchant: str,
    direction: str = "expense",
    currency: str = "CNY",
    category_hint: str | None = None,
    note: str | None = None,
    occurred_at: str | None = None,
) -> str:
    resp = await _call_internal("/api/v1/mcp/expense/create", body={
        "amount": amount,
        "direction": direction,
        "currency": currency,
        "merchant": merchant,
        "category_hint": category_hint,
        "note": note,
        "occurred_at": occurred_at,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── expense_search ──────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="expense_search",
    description="搜索账单（商户/备注模糊匹配）。",
)
async def expense_search(q: str = "", limit: int = 20) -> str:
    resp = await _call_internal("/api/v1/mcp/expense/search", body={
        "q": q,
        "limit": limit,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── expense_summary ─────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="expense_summary",
    description="获取当月账单汇总（总支出、笔数）。",
)
async def expense_summary() -> str:
    resp = await _call_internal("/api/v1/mcp/expense/summary", body={})
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── task_create ─────────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="task_create",
    description="创建任务/提醒。支持指定提醒时间、优先级等。",
)
async def task_create(
    title: str,
    remind_at: str | None = None,
    description: str | None = None,
    due_at: str | None = None,
    priority: str = "normal",
) -> str:
    resp = await _call_internal("/api/v1/mcp/task/create", body={
        "title": title,
        "description": description,
        "due_at": due_at,
        "remind_at": remind_at,
        "priority": priority,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── task_list ───────────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="task_list",
    description="列出活跃任务，可按状态筛选。",
)
async def task_list(task_status: str | None = None, limit: int = 20) -> str:
    resp = await _call_internal("/api/v1/mcp/task/list", body={
        "task_status": task_status,
        "limit": limit,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── task_complete ───────────────────────────────────────────────────────────

@cloud_mcp.tool(
    name="task_complete",
    description="将任务标记为已完成。",
)
async def task_complete(task_id: str) -> str:
    resp = await _call_internal("/api/v1/mcp/task/complete", body={
        "task_id": task_id,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── asset_create_upload_url ─────────────────────────────────────────────────

@cloud_mcp.tool(
    name="asset_create_upload_url",
    description="获取附件上传预签名 URL，用于上传图片/文件等。",
)
async def asset_create_upload_url(
    filename: str,
    mime_type: str | None = None,
    size_bytes: int | None = None,
    asset_type: str = "file",
) -> str:
    resp = await _call_internal("/api/v1/mcp/asset/create-upload-url", body={
        "filename": filename,
        "mime_type": mime_type,
        "size_bytes": size_bytes,
        "asset_type": asset_type,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── asset_register_external_url ─────────────────────────────────────────────

@cloud_mcp.tool(
    name="asset_register_external_url",
    description="注册外部链接作为附件（图床、飞书、Notion 等）。",
)
async def asset_register_external_url(
    external_url: str,
    title: str | None = None,
    asset_type: str = "link",
) -> str:
    resp = await _call_internal("/api/v1/mcp/asset/register-external-url", body={
        "external_url": external_url,
        "title": title,
        "asset_type": asset_type,
    })
    return json.dumps(resp, ensure_ascii=False, indent=2)


# ─── Internal Call ───────────────────────────────────────────────────────────

async def _call_internal(path: str, body: dict) -> dict:
    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0)) as client:
        resp = await client.post(
            f"http://127.0.0.1:{settings.api_port}{path}",
            json=body,
        )
        resp.raise_for_status()
        return resp.json()
