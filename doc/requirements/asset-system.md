# 附件与对象存储系统

## 1. 目标

附件系统支持备忘录中的图片、文件、PDF、PPT、思维导图、外部链接等内容。

原则：

- 数据库只存 metadata；
- 文件二进制存在对象存储；
- 外部链接可引用；
- 本地可缓存；
- 附件可被多个文档引用；
- 删除时必须考虑引用关系。

## 2. 资产类型

```text
image
pdf
ppt
mindmap
file
audio
video
link
embed
```

MVP 重点：

- image；
- pdf；
- ppt；
- mindmap；
- file；
- link。

## 3. 内部资产

内部资产是用户上传到 Lifly 的文件。

字段：

```text
id
user_id
kind = internal
storage_provider
storage_key
filename
mime_type
size_bytes
sha256
visibility
sync_status
```

访问方式：

```text
asset_id → 后端鉴权 → presigned_url → 客户端访问
```

## 4. 外部资产

外部资产是用户提供的图床、飞书、Notion、网页链接等。

字段：

```text
id
user_id
kind = external
external_url
external_provider
asset_type
title
preview_url
```

注意：

- 外部链接可能失效；
- 外部链接内容可能变化；
- 外部资源不保证离线可用；
- 后续提供“转存到我的空间”。

## 5. Markdown 引用格式

内部附件：

```markdown
![图片](asset://asset_id)

[[file:asset_id]]
[[ppt:asset_id]]
[[mindmap:asset_id]]
```

外部链接：

```markdown
https://example.com/file.pdf
```

## 6. 上传流程

```text
选择文件
    ↓
创建 asset metadata
    ↓
获取上传 URL
    ↓
上传对象存储
    ↓
通知后端完成
    ↓
写入 memo_asset_refs
```

## 7. 下载与缓存

客户端缓存：

```text
cache_key = asset_id + revision
```

缓存状态：

```text
not_cached
downloading
cached
failed
```

缓存可被用户清理。

## 8. 删除策略

如果 memo 被删除，不能立即删除 asset，因为 asset 可能被其他 memo 引用。

删除条件：

```text
asset 无任何引用
并且 owner 确认删除
并且不在回收站恢复期
```

后台清理孤儿附件。

## 9. 预览策略

MVP：

- 图片：直接预览；
- PDF：文件卡片 + 系统打开；
- PPT/PPTX：文件卡片 + 系统打开；
- 思维导图：文件卡片；
- 外链：链接卡片。

后续：

- PDF 内嵌预览；
- PPT 缩略图；
- 思维导图编辑；
- 外部链接自动抓取标题与摘要。

## 10. 容量限制

MVP 默认建议：

```text
单文件最大：50MB
图片可压缩
本地缓存可清理
外部链接不计入容量
```

正式商业化后需增加：

- 用户总容量；
- 上传流量限制；
- 超额提示；
- 付费扩容。
