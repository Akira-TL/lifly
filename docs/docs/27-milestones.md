# 27. Milestones

## M0 Repo Bootstrap & Technical Spikes

目标：建立仓库、工程骨架和高风险技术验证。

交付物：

```text
Monorepo 初始化
docs/ 入仓
Flutter 空项目
FastAPI 空项目
Cloud MCP 空项目
Docker Compose
PostgreSQL / Redis / MinIO / PowerSync
基础 CI
```

验收：clone 后可以启动基础开发环境；Windows/Android Flutter 项目可运行；FastAPI health check 可访问；Cloud MCP 可启动。

## M1 Local Data MVP

目标：客户端本地手动记录闭环。

交付物：本地 memo CRUD、本地 expense CRUD、本地 task CRUD、基础 SQLite/PowerSync schema、基础 UI。

验收：无网络时 Windows/Android 均可创建 memo/expense/task，重启后数据不丢。

## M2 Cloud Sync MVP

目标：云同步闭环。

交付物：登录、PostgreSQL schema、PowerSync、跨端同步、同步状态 UI、audit_logs、trash 状态机。

验收：Windows 创建 Android 可见；Android 离线创建后联网 Windows 可见；所有写操作有 audit_log。

## M3 Cloud MCP MVP

目标：AI/MCP 写入闭环。

交付物：Cloud MCP、memo_create、expense_create、task_create、capture_parse、capture_commit、capture_undo、MCP token、审计日志。

验收：MCP Client 可创建 memo/expense/task；混合输入可拆解；capture_undo 可撤销。

## M4 Assets & Import MVP

目标：附件与账单导入闭环。

交付物：附件上传、外链注册、Markdown asset:// 引用、通用/支付宝/微信 CSV parser、导入预览、批次回滚、重复检测。

验收：图片可上传并插入 memo；账单 CSV 可预览、去重、commit、rollback。

## M5 Windows Local MCP

目标：支持本地模型/离线 AI/私有部署。

交付物：Local MCP stdio、Local Core Bridge、共用 schema、写本地 SQLite、写 audit_log、联网后同步、Hermes 配置样例。
