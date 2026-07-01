# 99. 术语表

## Lifly

项目代号。AI-first / Chat-first 的个人生活数据系统。

## MCP

Model Context Protocol。Lifly 用 MCP 向 AI、Hermes、OpenClaw、机器人等暴露工具能力。

## Cloud MCP

运行在云端的 MCP Server，默认 AI 接入方式。

## Local MCP

运行在 Windows 桌面端的本地 MCP Server，用于本地模型、离线 AI、私有部署。

## Capture

用户自然语言原始输入，例如“一句话里面同时包含记账、任务和备忘”。

## Action

Capture 被解析后生成的具体动作，例如 expense_create、memo_create、task_create。

## Memo

泛化文本记录，包含 memo、journal、clip、doc。

## Asset

附件或外部资源引用。

## Internal Asset

用户上传到 Lifly 存储空间的私有附件。

## External Asset

用户提供的外部链接、图床链接、第三方文档链接。

## Ledger

记账领域。

## Transaction

账单交易。

## Task

任务或待办。

## Reminder

提醒，可挂在任务、日程、备忘录或账单上。

## CalendarEvent

日历事件，MVP 只预留。

## ImportBatch

导入批次，用于 CSV 导入预览、确认和回滚。

## AuditLog

审计日志，记录所有创建、修改、删除、导入、导出和 AI 操作。

## Tombstone

同步系统中保留的删除标记。内容已清除，但保留 entity_id 和 revision，防止旧数据被重新同步回来。

## PowerSync

用于 PostgreSQL 与客户端 SQLite 同步的系统。

## Object Storage

对象存储，例如 S3、R2、MinIO，用于存附件二进制。
