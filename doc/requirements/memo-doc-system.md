# 备忘录与文档系统

## 1. 定位

备忘录系统是 Lifly 的非结构化记录中心。它不只是短备忘，也承载日记、剪藏、长文档和附件引用。

## 2. 类型

```text
memo      普通备忘
journal   日记
clip      摘录/剪藏
doc       长文档
```

## 3. 数据结构

核心字段：

```text
title
content_markdown
type
tags
mood
asset_refs
source_capture_id
status
```

## 4. Markdown

MVP 采用 Markdown。原因：

- 简单；
- 易导出；
- 易同步；
- 易被 AI 处理；
- 可与 Obsidian 等工具兼容；
- 后续可演进为块编辑器。

## 5. 附件引用

正文通过 asset:// 引用内部附件。附件本体不嵌入正文。

示例：

```markdown
# 今天的想法

这里是一张图：

![图](asset://a_123)

这里是一个 PPT：

[[ppt:a_456]]
```

## 6. 日记模式

日记与普通 memo 的区别：

- 默认按日期聚合；
- 可记录 mood；
- 可参与每日/每周总结；
- AI 输入“写日记”时自动归类为 journal。

## 7. 剪藏模式

Clip 主要用于：

- 链接；
- 外部文档；
- 文章摘录；
- 图片外链。

MVP 可先只保存 URL 和备注。

## 8. 搜索

MVP 搜索：

- 标题；
- 正文；
- 标签；
- 类型；
- 日期。

后续搜索：

- 附件 OCR；
- PDF 文本；
- 语义搜索；
- RAG。

## 9. 导出

必须支持：

- 单篇 Markdown 导出；
- 按日期导出 journal；
- 附件打包导出；
- 全量 JSON 导出。

## 10. AI 能力

第一版 AI 能力：

- 创建备忘；
- 创建日记；
- 搜索备忘；
- 总结某天记录；
- 混合输入中拆分备忘。

长期 AI 分类能力：

```text
AI 自动标签
AI 分类置信度
AI 待分类 / AI 建议 / AI 已确认
用户确认 / 拒绝分类
按标签和分类状态筛选
标签统计
```

`Memo.tags` 只能作为轻量展示字段，不能承担完整分类系统。结构化分类应使用：

```text
memo_classifications
  label
  label_type
  source
  confidence
  status

tag_metadata
  name
  kind
  color_token
  icon_token
  sort_order
```

UI 可以展示：

```text
[清单] [生活] [AI 已分类]
[读书] [知识] [AI 建议]
[待整理]
```

但这些状态必须来自接口字段，不能由客户端根据 tag 文本猜测。

不做：

- 自动改写用户正文；
- 自动删除文档；
- 飞书式协同编辑。
