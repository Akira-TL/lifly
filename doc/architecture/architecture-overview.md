# 总体架构

## 1. 架构目标

Lifly 的架构目标是：

- 本地优先；
- 云端同步；
- AI/MCP 可调用；
- Windows + Android 优先；
- 后续多平台可扩展；
- 附件与文本分离；
- 所有操作可审计。

## 2. 高层架构

```text
                 ┌──────────────────────┐
                 │  OpenClaw / Hermes    │
                 │  QQ Bot / WeChat Bot  │
                 │  App 内 AI Chat       │
                 └──────────┬───────────┘
                            │ MCP
                            ▼
                 ┌──────────────────────┐
                 │ Cloud MCP Server      │
                 │ TypeScript            │
                 └──────────┬───────────┘
                            │ Internal API
                            ▼
┌────────────────────────────────────────────────────┐
│ Cloud Backend                                      │
│ FastAPI + PostgreSQL + PowerSync + Object Storage  │
└──────────┬──────────────────────┬──────────────────┘
           │                      │
           │ PowerSync             │ Presigned URL / Asset API
           ▼                      ▼
┌─────────────────────┐     ┌──────────────────────┐
│ Flutter Client       │     │ Object Storage        │
│ Windows / Android    │     │ R2 / S3 / MinIO       │
│ SQLite local store   │     └──────────────────────┘
└──────────┬──────────┘
           │
           │ Windows only
           ▼
┌─────────────────────┐
│ Local MCP Server     │
│ stdio                │
│ local AI / Hermes    │
└─────────────────────┘
```

## 3. 运行模式

### 3.1 在线云端模式

默认模式。用户通过 App 内 AI、Hermes、OpenClaw、机器人等访问云端 MCP，云端 MCP 调用后端 API，写入云端数据库，再通过 PowerSync 同步到客户端。

### 3.2 离线手动模式

无网络时，Windows/Android 客户端仍可手动创建备忘录、账单、任务。数据写入本地 SQLite。恢复网络后同步到云端。

### 3.3 Windows 本地 AI 模式

Windows 桌面端可启动本地 MCP Server。本地 Hermes 或本地模型通过 stdio MCP 调用本地服务，写入本地 SQLite。恢复网络后通过 PowerSync 同步到云端。

## 4. 边界原则

### 4.1 AI 不直接操作数据库

AI 只能调用 MCP 工具。MCP 工具再调用统一业务逻辑。所有写操作必须写入 audit_logs。

### 4.2 附件不进入同步数据库

PowerSync 同步结构化数据和附件 metadata，不同步二进制文件。附件实际内容走对象存储，本地只缓存。

### 4.3 本地 MCP 不绕过业务规则

本地 MCP 必须复用云端同一套 tool schema、实体状态机、审计规则和删除规则。

### 4.4 用户数据可导出

所有核心数据必须提供导出路径，避免数据锁定。

## 5. 主要服务

| 服务 | 职责 |
|---|---|
| Flutter Client | Windows/Android 客户端，本地记录、查看、编辑、缓存 |
| FastAPI Backend | 业务 API、认证、同步写入、导入、附件管理 |
| PowerSync | PostgreSQL 与客户端 SQLite 同步 |
| Cloud MCP Server | 云端 MCP 工具暴露 |
| Local MCP Server | Windows 本地 MCP |
| Object Storage | 附件二进制存储 |
| Worker | CSV 解析、导入、缩略图、导出、清理任务 |
