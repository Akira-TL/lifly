#!/bin/bash
set -e

API="http://localhost:8310/api/v1"
PASS=0; FAIL=0

check() {
    if echo "$2" | grep -q "$3"; then echo "  ✅ $1"; PASS=$((PASS+1))
    else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi
}

echo "=== P7 第三方生态测试 ==="

# ── 1. 插件列表 ──
echo -e "\n--- 1. 插件列表 ---"
PLUGINS=$(python3 -c "
import urllib.request, json
r = urllib.request.urlopen('$API/plugins')
print(r.read().decode()[:500])
")
echo "$PLUGINS"
check "包含 lifly.core.import" "lifly.core.import" "$PLUGINS"
check "包含 lifly.core.capture" "lifly.core.capture" "$PLUGINS"

# ── 2. 机器人列表 ──
echo -e "\n--- 2. 机器人列表 ---"
BOTS=$(python3 -c "
import urllib.request, json
r = urllib.request.urlopen('$API/robots')
d = json.load(r)['data']
for b in d['robots']: print(f\"  {b['id']}: {b['name']}\")
")
echo "$BOTS"
check "包含 lifly-bot" "lifly-bot" "$BOTS"
check "包含 finance-bot" "finance-bot" "$BOTS"

# ── 3. 机器人详情 ──
echo -e "\n--- 3. 机器人详情 (lifly-bot) ---"
BOT=$(python3 -c "
import urllib.request, json
r = urllib.request.urlopen('$API/robots/lifly-bot')
d = json.load(r)['data']
print(f'name={d[\"name\"]}, tools={len(d[\"tools\"])}, endpoint={d[\"mcp_endpoint\"]}')
")
echo "$BOT"
check "包含 tools" "tools" "$BOT"

# ── 4. 机器人 System Prompt ──
echo -e "\n--- 4. System Prompt ---"
PROMPT=$(python3 -c "
import urllib.request
r = urllib.request.urlopen('$API/robots/lifly-bot/system-prompt')
print(r.read().decode()[:150])
")
echo "$PROMPT"
check "包含 Lifly" "Lifly" "$PROMPT"

# ── 5. ICS 导出解析 ──
echo -e "\n--- 5. ICS 往返测试 ---"
ICS_TEST=$(python3 -c "
from app.modules.imexport.ics_handler import export_ics, parse_ics
events = [
    {'title': '测试事件', 'description': '测试描述', 'start_at': '2026-06-23T12:00:00Z', 'end_at': '2026-06-23T13:00:00Z', 'location': '办公室', 'rrule': None},
    {'title': '全天事件', 'start_at': '2026-06-24', 'end_at': None, 'location': None, 'rrule': None, 'description': None},
]
ics = export_ics(events)
result = parse_rics(ics.encode())
print(f'exported_bytes={len(ics)} parsed_rows={result.total_rows} row0_title={result.rows[0].parsed[\"title\"] if result.rows else \"none\"}')
")
echo "$ICS_TEST"
check "parsed_rows=2" "parsed_rows=2" "$ICS_TEST"

# ── 6. Notion ZIP 解析 ──
echo -e "\n--- 6. Notion ZIP 解析 ---"
NOTION_TEST=$(python3 -c "
import zipfile, io
from app.modules.imexport.third_party_parser import parse_notion_markdown_zip
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as zf:
    zf.writestr('page1.md', '---\ntitle: 测试文档\ntags: [test, notion]\n---\n# Hello\n\n这是正文。')
    zf.writestr('page2.md', '# 无Frontmatter\n\n内容。')
    zf.writestr('_attachments/img.png', b'fake-png')
result = parse_notion_markdown_zip(buf.getvalue())
print(f'total={result.total_rows} rows[0].title={result.rows[0].parsed.get(\"title\")} rows[0].tags={result.rows[0].parsed.get(\"tags\")}')
")
echo "$NOTION_TEST"
check "total=3" "total=3" "$NOTION_TEST"

# ── 7. Obsidian MD 解析 ──
echo -e "\n--- 7. Obsidian Markdown 解析 ---"
OBSIDIAN_TEST=$(python3 -c "
from app.modules.imexport.third_party_parser import parse_obsidian_markdown
text = '''---
title: Obsidian笔记
tags: [obsidian, idea]
created_at: 2025-01-15
---
# 笔记标题

这是一个段落。引用了 [[另一篇笔记]] 和 [[项目/详情|项目详情]]。

内联标签 #生产力 #效率 。'''
result = parse_obsidian_markdown(text.encode())
r = result.rows[0]
print(f'total={result.total_rows} title={r.parsed.get(\"title\")} tags={r.parsed.get(\"tags\")} content_has_link={r.parsed[\"content_markdown\"][:100]}')
")
echo "$OBSIDIAN_TEST"
check "total=1" "total=1" "$OBSIDIAN_TEST"
check "tags包含生产力" "生产力" "$OBSIDIAN_TEST"

# ── 8. 飞书 JSON 解析 ──
echo -e "\n--- 8. 飞书 Doc JSON 解析 ---"
FEISHU_TEST=$(python3 -c "
import json
from app.modules.imexport.third_party_parser import parse_feishu_doc_json
doc = {'blocks': [
    {'type': 'heading1', 'heading1': {'elements': [{'text_run': {'content': '飞书标题'}}]}},
    {'type': 'text', 'text': {'elements': [{'text_run': {'content': '这是一段正文。'}}]}},
    {'type': 'bullet', 'bullet': {'elements': [{'text_run': {'content': '列表项1'}}]}},
]}
result = parse_feishu_doc_json(json.dumps(doc).encode())
print(f'total={result.total_rows} title={result.rows[0].parsed.get(\"title\")} content_has_heading={result.rows[0].parsed[\"content_markdown\"][:80]}')
")
echo "$FEISHU_TEST"
check "total=1" "total=1" "$FEISHU_TEST"

echo -e "\n=== 测试完成: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ] || exit 1
