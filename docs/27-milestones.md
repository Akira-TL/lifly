# 27. Lifly Milestones

## M0：Repo Bootstrap & Governance Alignment

目标：完成仓库命名、文档入仓、AI 执行规范、基础工程结构和本地开发设施对齐。

验收：

- 项目命名统一为 Lifly / lifly
- docs/ 中存在架构冻结与 AI 执行文档
- README 指向正确文档
- docker-compose 可作为本地基础设施入口
- FastAPI health check 可访问

## M1：Local Data MVP

目标：客户端本地手动记录闭环。

范围：

- memo CRUD
- expense CRUD
- task CRUD
- 本地 SQLite / PowerSync schema
- 基础 UI

验收：

- 无网络时可创建 memo / expense / task
- 重启后数据不丢

## M2：Cloud Sync MVP

目标：云同步闭环。

范围：

- 登录
- PostgreSQL schema
- PowerSync 集成
- 跨端同步
- audit_logs
- trash 状态机

验收：

- Windows 创建，Android 可见
- Android 离线创建，联网后 Windows 可见
- 删除状态跨端一致

## M3：Cloud MCP MVP

目标：AI/MCP 写入闭环。

范围：

- Cloud MCP
- memo_create
- expense_create
- task_create
- capture_parse
- capture_commit
- capture_undo

验收：

- MCP Client 可创建 memo / expense / task
- 混合输入可拆成多个 action
- 所有写入有 audit_log

## M4：Assets & Import MVP

目标：附件与 CSV 导入闭环。

范围：

- asset_create_upload_url
- asset_register_external_url
- 对象存储适配
- Markdown asset 引用
- 通用 CSV / 支付宝 CSV / 微信 CSV
- 导入预览与批次回滚

## M5：Windows Local MCP

目标：支持本地模型、离线 AI、私有部署。

范围：

- Local MCP stdio
- Local Core Bridge
- 与 Cloud MCP 共用 schema
- 写本地 SQLite
- 联网后同步
