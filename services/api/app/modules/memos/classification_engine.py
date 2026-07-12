from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import re

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import Memo, MemoClassification, TagMetadata


@dataclass(frozen=True)
class TagRule:
    tag: str
    kind: str
    color_token: str
    icon_token: str
    sort_order: int
    keywords: tuple[str, ...]
    reason: str


@dataclass(frozen=True)
class MemoClassificationSuggestion:
    tag: str
    confidence: float
    reason: str


TAG_RULES: tuple[TagRule, ...] = (
    TagRule(
        tag="清单",
        kind="memo",
        color_token="green",
        icon_token="checklist",
        sort_order=10,
        keywords=("清单", "准备", "采购", "买", "装备", "待办", "事项", "checklist", "todo"),
        reason="内容包含清单、准备或采购语义。",
    ),
    TagRule(
        tag="读书",
        kind="memo",
        color_token="blue",
        icon_token="book",
        sort_order=20,
        keywords=("读书", "书摘", "读后感", "摘录", "章节", "作者", "阅读", "《", "》"),
        reason="内容包含阅读、书籍或摘录语义。",
    ),
    TagRule(
        tag="工作",
        kind="memo",
        color_token="orange",
        icon_token="briefcase",
        sort_order=30,
        keywords=("项目", "会议", "复盘", "需求", "开发", "PR", "评审", "排期", "周报", "文档"),
        reason="内容包含工作、项目或协作语义。",
    ),
    TagRule(
        tag="旅行",
        kind="memo",
        color_token="purple",
        icon_token="map",
        sort_order=40,
        keywords=("旅行", "出行", "行程", "机票", "酒店", "露营", "路线", "签证", "周末游"),
        reason="内容包含旅行、出行或路线安排语义。",
    ),
    TagRule(
        tag="健康",
        kind="memo",
        color_token="cyan",
        icon_token="health",
        sort_order=50,
        keywords=("健身", "跑步", "体重", "睡眠", "体检", "运动", "饮食", "训练", "健康"),
        reason="内容包含健康、运动或身体状态语义。",
    ),
    TagRule(
        tag="财务",
        kind="memo",
        color_token="teal",
        icon_token="wallet",
        sort_order=60,
        keywords=("账单", "消费", "预算", "发票", "报销", "收入", "支出", "流水", "付款"),
        reason="内容包含账单、预算或收支语义。",
    ),
    TagRule(
        tag="灵感",
        kind="memo",
        color_token="violet",
        icon_token="sparkles",
        sort_order=70,
        keywords=("想法", "灵感", "方案", "脑暴", "构思", "创意", "idea"),
        reason="内容包含想法、方案或创意语义。",
    ),
    TagRule(
        tag="生活",
        kind="memo",
        color_token="gray",
        icon_token="home",
        sort_order=90,
        keywords=("家庭", "生活", "购物", "整理", "家里", "日常", "朋友", "周末"),
        reason="内容包含生活、家庭或日常记录语义。",
    ),
)


def classify_memo_text(*, title: str | None, content: str, memo_type: str, tags: list | None) -> list[MemoClassificationSuggestion]:
    text = "\n".join([title or "", content or "", " ".join(str(tag) for tag in tags or [])]).lower()
    suggestions: list[MemoClassificationSuggestion] = []
    for rule in TAG_RULES:
        hit_count = sum(1 for keyword in rule.keywords if keyword.lower() in text)
        if hit_count == 0:
            continue
        confidence = min(0.92, 0.58 + hit_count * 0.08)
        if rule.tag == "清单" and _looks_like_list(content):
            confidence = max(confidence, 0.86)
        if rule.tag == "读书" and ("《" in text and "》" in text):
            confidence = max(confidence, 0.88)
        suggestions.append(MemoClassificationSuggestion(rule.tag, confidence, rule.reason))

    if memo_type == "journal" and not any(item.tag == "生活" for item in suggestions):
        suggestions.append(MemoClassificationSuggestion("生活", 0.52, "日记类内容默认进入生活记录。"))

    if not suggestions:
        suggestions.append(MemoClassificationSuggestion("生活", 0.42, "未命中明确分类，先作为生活记录待后续确认。"))
        suggestions.append(MemoClassificationSuggestion("待整理", 0.40, "AI 置信度较低，需要用户稍后整理。"))

    deduped: dict[str, MemoClassificationSuggestion] = {}
    for item in suggestions:
        existing = deduped.get(item.tag)
        if existing is None or item.confidence > existing.confidence:
            deduped[item.tag] = item
    return sorted(deduped.values(), key=lambda item: (-item.confidence, item.tag))[:4]


def tag_rule_for(tag: str) -> TagRule:
    for rule in TAG_RULES:
        if rule.tag == tag:
            return rule
    return TagRule(
        tag=tag,
        kind="memo",
        color_token="gray",
        icon_token="tag",
        sort_order=200,
        keywords=(),
        reason="用户自定义标签。",
    )


async def ensure_tag_metadata(db: AsyncSession, *, user_id: str, tag: str, kind: str = "memo") -> TagMetadata:
    rule = tag_rule_for(tag)
    result = await db.execute(
        select(TagMetadata).where(
            TagMetadata.user_id == user_id,
            TagMetadata.name == tag,
            TagMetadata.kind == kind,
        )
    )
    metadata = result.scalar_one_or_none()
    if metadata is None:
        metadata = TagMetadata(
            user_id=user_id,
            name=tag,
            kind=kind,
            color_token=rule.color_token,
            icon_token=rule.icon_token,
            sort_order=rule.sort_order,
            status="active",
        )
        db.add(metadata)
    else:
        metadata.status = "active"
        metadata.color_token = metadata.color_token or rule.color_token
        metadata.icon_token = metadata.icon_token or rule.icon_token
        metadata.sort_order = metadata.sort_order if metadata.sort_order is not None else rule.sort_order
    await db.flush()
    return metadata


async def generate_memo_classifications(
    db: AsyncSession,
    memo: Memo,
    *,
    replace_suggested: bool = True,
    include_user_tags: bool = True,
) -> list[MemoClassification]:
    now = datetime.now(timezone.utc)
    if replace_suggested:
        await db.execute(
            delete(MemoClassification).where(
                MemoClassification.user_id == memo.user_id,
                MemoClassification.memo_id == memo.id,
                MemoClassification.source == "ai",
                MemoClassification.status == "suggested",
            )
        )

    existing_result = await db.execute(
        select(MemoClassification).where(
            MemoClassification.user_id == memo.user_id,
            MemoClassification.memo_id == memo.id,
            MemoClassification.status != "rejected",
        )
    )
    existing_by_tag = {item.tag: item for item in existing_result.scalars().all()}

    created: list[MemoClassification] = []
    if include_user_tags:
        for raw_tag in memo.tags or []:
            tag = str(raw_tag).strip()
            if not tag:
                continue
            await ensure_tag_metadata(db, user_id=memo.user_id, tag=tag)
            if tag in existing_by_tag:
                continue
            item = MemoClassification(
                user_id=memo.user_id,
                memo_id=memo.id,
                tag=tag,
                source="user",
                status="confirmed",
                confidence=1.0,
                reason="来自用户手动标签。",
                confirmed_at=now,
            )
            db.add(item)
            created.append(item)
            existing_by_tag[tag] = item

    for suggestion in classify_memo_text(
        title=memo.title,
        content=memo.content_markdown,
        memo_type=memo.type,
        tags=memo.tags,
    ):
        await ensure_tag_metadata(db, user_id=memo.user_id, tag=suggestion.tag)
        existing = existing_by_tag.get(suggestion.tag)
        if existing and existing.status == "confirmed":
            continue
        item = MemoClassification(
            user_id=memo.user_id,
            memo_id=memo.id,
            tag=suggestion.tag,
            source="ai",
            status="suggested",
            confidence=suggestion.confidence,
            reason=suggestion.reason,
        )
        db.add(item)
        created.append(item)
        existing_by_tag[suggestion.tag] = item

    await db.flush()
    result = await db.execute(
        select(MemoClassification)
        .where(MemoClassification.user_id == memo.user_id, MemoClassification.memo_id == memo.id)
        .order_by(MemoClassification.updated_at.desc())
    )
    return list(result.scalars().all())


def _looks_like_list(content: str) -> bool:
    lines = [line.strip() for line in (content or "").splitlines() if line.strip()]
    if len(lines) >= 3:
        marker_count = sum(1 for line in lines if re.match(r"^([-*•]|\d+[.)]|\[[ xX]\])\s*", line))
        return marker_count >= 2
    return "、" in content and len(content.split("、")) >= 4
