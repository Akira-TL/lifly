from __future__ import annotations

import re
import uuid
import hashlib
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone as tz

TZ_SHANGHAI = tz(timedelta(hours=8))

# 常见金额模式: 花了18, 消费50, 18元, 18块, ¥18, ￥18
AMOUNT_RE = re.compile(r"(?:花了?|消费|支出)\s*(\d+(?:\.\d{1,2})?)|(\d+(?:\.\d{1,2})?)\s*[元块]|[¥￥](\d+(?:\.\d{1,2})?)")
# 时间模式: 晚上8点, 下午3点, 明天10:30, 8:00, 今晚, 现在
TIME_RE = re.compile(
    r"(早上|中午|下午|晚上|今晚|明天|后天|今天|明早|今早)?\s*(\d{1,2})[:：](\d{2})|"
    r"(早上|中午|下午|晚上|今晚|明天|后天|今天|明早|今早)?\s*(\d{1,2})\s*点(?:\s*(\d{2})\s*分?)?"
)
# 商户模式
MERCHANT_RE = re.compile(r"(?:在|去|到)\s*(.{1,20}?)\s*(?:花了?|消费|吃饭|用餐|买了|购物)")
# 任务提示词
TASK_KEYWORDS = ["提醒", "记得", "别忘了", "要做", "任务", "TODO"]
# 情绪模式
MOOD_KEYWORDS = ["累", "开心", "难过", "焦虑", "兴奋", "感恩", "压力", "充实", "无聊", "紧张"]

CAPTURE_STORE: dict[str, CaptureSession] = {}


@dataclass
class CandidateAction:
    type: str  # memo_create, expense_create, task_create
    payload: dict
    confidence: float
    raw_text: str = ""


@dataclass
class ParseResult:
    capture_id: str
    actions: list[CandidateAction] = field(default_factory=list)
    requires_confirmation: bool = False


@dataclass
class CaptureSession:
    capture_id: str
    original_text: str
    actions: list[CandidateAction] = field(default_factory=list)
    created_at: datetime = field(default_factory=lambda: datetime.now(TZ_SHANGHAI))
    committed: bool = False


def parse_mixed_input(text: str, timezone_str: str = "Asia/Shanghai", locale: str = "zh-CN") -> ParseResult:
    capture_id = str(uuid.uuid4())
    result = ParseResult(capture_id=capture_id)
    remaining = text

    # ── 1. 尝试提取金额/账单 ──
    amount_match = AMOUNT_RE.search(text)
    if amount_match:
        amount_str = amount_match.group(1) or amount_match.group(2) or amount_match.group(3)
        if amount_str:
            amount = float(amount_str)
            # 提取商户
            merchant = "未知商户"
            m_match = MERCHANT_RE.search(text)
            if m_match:
                merchant = m_match.group(1).strip()

            occurred_at = datetime.now(TZ_SHANGHAI).replace(
                hour=12, minute=0, second=0, microsecond=0
            )

            # 尝试提取时间
            time_match = TIME_RE.search(text)
            if time_match:
                parsed = _parse_time(time_match)
                if parsed:
                    occurred_at = parsed

            result.actions.append(CandidateAction(
                type="expense_create",
                payload={
                    "amount": amount,
                    "currency": "CNY",
                    "direction": "expense",
                    "merchant": merchant,
                    "category_hint": _infer_category(text),
                    "occurred_at": occurred_at.isoformat(),
                },
                confidence=0.85,
                raw_text=amount_match.group(0),
            ))

    # ── 2. 尝试提取任务/提醒 ──
    task_texts: list[str] = []
    # 找"提醒我X"、"X点提醒"等模式
    remind_pattern = re.compile(
        r"(?:记得|别忘了|提醒我?|要做)\s*(.{2,40}?)(?:，|,|。|$|\s*(?:早上|中午|下午|晚上|在|到|明天))"
    )
    for m in remind_pattern.finditer(text):
        task_desc = m.group(1).strip()
        if task_desc and len(task_desc) > 1:
            task_texts.append(task_desc)

    # 也检查关键词
    for kw in TASK_KEYWORDS:
        kw_pos = text.find(kw)
        if kw_pos >= 0:
            after = text[kw_pos + len(kw):].strip()
            # 取到下一个逗号/句号
            end = min([after.find(c) for c in "，,。；;！!"] if any(c in after for c in "，,。；;！!") else [len(after)])
            snippet = after[:end].strip()
            if snippet and len(snippet) > 1 and snippet not in task_texts:
                task_texts.append(snippet)

    for task_text in task_texts[:2]:  # 最多2个任务
        remind_at = None
        # 这个任务后面是否有时间
        pos = text.find(task_text)
        if pos >= 0:
            after_text = text[pos + len(task_text):pos + len(task_text) + 30]
            tm = TIME_RE.search(after_text)
            if tm:
                remind_at = _parse_time(tm)

        if remind_at is None:
            remind_at = datetime.now(TZ_SHANGHAI).replace(
                hour=20, minute=0, second=0, microsecond=0
            ).isoformat()
        else:
            remind_at = remind_at.isoformat()

        result.actions.append(CandidateAction(
            type="task_create",
            payload={
                "title": task_text,
                "remind_at": remind_at,
                "priority": "normal",
            },
            confidence=0.80,
            raw_text=task_text,
        ))

    # ── 3. 尝试提取备忘/日记 ──
    memo_triggers = re.compile(r"(?:记一下|记一记|记录一下|备忘|日记|日记一下)")
    for m in memo_triggers.finditer(text):
        start = m.end()
        rest = text[start:].strip()
        # 取到下一个句号/句末
        end = min([rest.find(c) for c in "。！!；;"] if any(c in rest for c in "。！!；;") else [len(rest)])
        content = rest[:end].strip()
        if content:
            # 检测情绪
            mood = None
            for mw in MOOD_KEYWORDS:
                if mw in content:
                    mood = mw
                    break

            result.actions.append(CandidateAction(
                type="memo_create",
                payload={
                    "type": "journal",
                    "content_markdown": content,
                    "mood": mood,
                },
                confidence=0.78,
                raw_text=content,
            ))

    # ── 4. 如果没有解析到任何动作，当作备忘处理 ──
    if not result.actions:
        result.actions.append(CandidateAction(
            type="memo_create",
            payload={
                "type": "memo",
                "content_markdown": text,
            },
            confidence=0.40,
            raw_text=text,
        ))
        result.requires_confirmation = True

    # 存储 session
    CAPTURE_STORE[capture_id] = CaptureSession(
        capture_id=capture_id,
        original_text=text,
        actions=result.actions,
    )

    # 清理过期 session（>1小时）
    now = datetime.now(TZ_SHANGHAI)
    expired = [k for k, v in CAPTURE_STORE.items() if (now - v.created_at).total_seconds() > 3600]
    for k in expired:
        del CAPTURE_STORE[k]

    return result


def _parse_time(match: re.Match) -> datetime | None:
    now = datetime.now(TZ_SHANGHAI)
    prefix = match.group(1) or match.group(4) or ""
    hour = int(match.group(2) or match.group(5) or 0)
    minute = int(match.group(3) or match.group(6) or 0)

    if "早上" in prefix or "早" in prefix:
        pass  # morning -> keep hour as-is
    elif "中午" in prefix:
        hour = 12
    elif "下午" in prefix:
        if hour < 12:
            hour += 12
    elif "晚上" in prefix or "今晚" in prefix:
        if hour < 12:
            hour += 12

    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)

    if "明天" in prefix:
        target += timedelta(days=1)
    elif "后天" in prefix:
        target += timedelta(days=2)

    return target


def _infer_category(text: str) -> str:
    cats = {
        "食堂": "餐饮", "餐厅": "餐饮", "饭": "餐饮", "外卖": "餐饮",
        "超市": "购物", "买了": "购物", "购物": "购物",
        "公交": "交通", "地铁": "交通", "打车": "交通", "滴滴": "交通",
    }
    for kw, cat in cats.items():
        if kw in text:
            return cat
    return "未分类"
