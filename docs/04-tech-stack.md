# 04. 技术选型

## 1. 客户端

### 选择

```text
Flutter + Dart
PowerSync Flutter SDK
SQLite
Markdown Editor + Custom Renderer
```

### 原因

- 一套代码支持 Windows/Android，并可扩展到 iOS/macOS/Linux/Web；
- Flutter 不是 Chromium 套壳；
- 对表单、列表、时间线、账单、任务等应用足够适合；
- 与 PowerSync Flutter SDK 路线兼容。

## 2. 后端

### 选择

```text
FastAPI
PostgreSQL
PowerSync
Redis
Background Worker
Object Storage
```

### 原因

- Python 生态适合账单解析、AI 解析、文本处理；
- FastAPI 工程简单，适合快速迭代；
- PostgreSQL 是云端核心数据源；
- PowerSync 负责同步；
- Redis 和 Worker 处理导入、导出、附件处理等异步任务。

## 3. MCP Server

### 选择

```text
TypeScript
MCP SDK
Cloud MCP: Streamable HTTP
Local MCP: stdio
```

### 原因

- TypeScript 适合定义工具 schema；
- 云端 MCP 适合远程调用；
- stdio MCP 适合本地 Hermes/OpenClaw/桌面 Agent；
- Cloud MCP 和 Local MCP 共享 tool schema。

## 4. 对象存储

### 选择

```text
开发环境：MinIO
生产环境：Cloudflare R2 / AWS S3
访问方式：Presigned URL
```

### 原因

- 附件不适合存在数据库；
- 对象存储便于容量管理；
- Presigned URL 可以实现临时授权访问；
- R2/S3/MinIO 都可以用 S3-like API 适配。

## 5. 数据同步

### 选择

```text
PowerSync
```

### 原因

- 客户端本地 SQLite；
- 云端 PostgreSQL；
- 支持 offline-first；
- 避免自研复杂同步系统。

## 6. 认证

MVP 可使用成熟 Auth 方案。建议：

```text
本地模式：免登录
云同步模式：登录
云端 MCP：Bearer Token / API Token
外部机器人：独立 token
本地 MCP：本机授权
```

## 7. 不选方案说明

### 不选 Electron

原因：资源占用较高，不符合“不要每个软件都是 Chrome”的要求。

### 不选纯 Web/PWA

原因：离线能力、桌面本地 MCP、本地文件缓存和平台集成会受限。

### 不自研同步

原因：同步系统复杂，后期迁移成本高。
