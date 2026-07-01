from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import PlainTextResponse
from app.schemas.common import ApiResponse
from app.modules.plugins.registry import get_registry

router = APIRouter()


# ─── Plugins: List ────────────────────────────────────────────────────────────

@router.get("/plugins", response_model=ApiResponse)
async def list_plugins():
    return ApiResponse(data={"plugins": get_registry().list_manifest()})


# ─── Robots: Templates ────────────────────────────────────────────────────────

ROBOT_TEMPLATES: dict[str, dict] = {
    "lifly-bot": {
        "id": "lifly-bot",
        "name": "Lifly 通用助理",
        "description": "通用生活数据助理，支持计账、备忘、任务创建",
        "system_prompt":
            "你是 Lifly 通用生活助理。你的任务是帮助用户将自然语言转换为结构化生活数据。\n\n"
            "你可以：\n"
            "- 记账：识别金额、商户、时间、分类，调用 expense_create\n"
            "- 备忘：记录想法、日记、灵感，调用 memo_create\n"
            "- 任务：创建提醒任务，调用 task_create\n"
            "- 搜索：查询历史记录，调用 memo_search/expense_search\n\n"
            "对于模糊输入，先调用 capture_parse 进行解析，向用户确认后再 commit。\n"
            "所有操作都可以撤销，用户回复撤销即可。",
        "tools": [
            "capture_parse", "capture_commit", "capture_undo",
            "memo_create", "memo_search",
            "expense_create", "expense_search", "expense_summary",
            "task_create", "task_list", "task_complete",
        ],
        "mcp_endpoint": "http://localhost:8310/mcp",
        "tags": ["通用", "入门"],
    },
    "finance-bot": {
        "id": "finance-bot",
        "name": "财务记账助理",
        "description": "专注账单记录与财务分析",
        "system_prompt": (
            "你是 Lifly 财务记账助理。专注于账单记录和财务分析。\n\n"
            "核心能力：\n"
            "- 快速记账：从自然语言提取金额/商户/分类\n"
            "- 查询账单：按时间/金额/商户搜索\n"
            "- 月度汇总：自动统计当月支出和收入\n"
            "- 导入CSV：支持支付宝/微信账单导入\n\n"
            "大额消费（>500元）会自动提醒用户确认。"
        ),
        "tools": [
            "expense_create", "expense_search", "expense_summary",
            "capture_parse", "capture_commit", "capture_undo",
        ],
        "mcp_endpoint": "http://localhost:8310/mcp",
        "tags": ["财务", "记账"],
    },
    "journal-bot": {
        "id": "journal-bot",
        "name": "日记助手",
        "description": "帮助记录日记、反思和灵感",
        "system_prompt": (
            "你是 Lifly 日记助手。帮助用户记录生活、反思和灵感。\n\n"
            "能力：\n"
            "- 记录日记/反思（journal 类型）\n"
            "- 收集灵感/想法（clip 类型）\n"
            "- 搜索过往日记\n"
            "- 识别情绪关键词（开心/难过/焦虑/感恩等）\n\n"
            "写作风格：温暖、简洁、尊重隐私。"
        ),
        "tools": [
            "memo_create", "memo_search",
            "capture_parse", "capture_commit", "capture_undo",
        ],
        "mcp_endpoint": "http://localhost:8310/mcp",
        "tags": ["日记", "写作"],
    },
}


@router.get("/robots", response_model=ApiResponse)
async def list_robots():
    items = []
    for robot in ROBOT_TEMPLATES.values():
        items.append({
            "id": robot["id"],
            "name": robot["name"],
            "description": robot["description"],
            "tags": robot["tags"],
        })
    return ApiResponse(data={"robots": items})


@router.get("/robots/{robot_id}", response_model=ApiResponse)
async def get_robot(robot_id: str):
    robot = ROBOT_TEMPLATES.get(robot_id)
    if not robot:
        raise HTTPException(status_code=404, detail="Robot template not found")
    return ApiResponse(data=robot)


@router.get("/robots/{robot_id}/system-prompt", response_class=PlainTextResponse)
async def get_robot_prompt(robot_id: str):
    robot = ROBOT_TEMPLATES.get(robot_id)
    if not robot:
        raise HTTPException(status_code=404, detail="Robot template not found")
    return robot["system_prompt"]
