# 27. Lifly Milestones

## M0：Repo Bootstrap & Governance Alignment

状态：已完成。

目标：完成仓库命名、文档入仓、AI 执行规范、基础工程结构和本地开发设施对齐。

验收：

- 项目命名统一为 Lifly / lifly
- docs/ 中存在架构冻结与 AI 执行文档
- README 指向正确文档
- docker-compose 可作为本地基础设施入口
- FastAPI health check 可访问

## M1：Local Data MVP

状态：已完成。

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

状态：已完成。

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

## M3：AI Write / MCP 全量闭环

状态：已完成，最终 tag：`v0.4.11`。

目标：AI/MCP 写入、确认、撤销、审计和诊断形成完整闭环。

范围：

- Cloud MCP / Local MCP 共用 packages/protocol tool schema
- Cloud MCP 直接写入 memo / expense / task / asset ref
- capture_parse / capture_commit / capture_undo
- AI undo 进入 ai_trashed，不物理删除
- Flutter AI 写入入口
- AI 写入审计摘要
- Cloud / Local MCP parity tests
- v0.4 AI Write release gate

验收：

- MCP Client 可创建 memo / expense / task / asset ref
- 混合输入可拆成多个 action
- 可选择部分 action 提交
- 所有 AI 写入和撤销有 audit_log
- Flutter 可进行 AI parse / commit / undo
- `bash scripts/check-v0.4-ai-write.sh` 通过

已知边界：

- Local MCP 属于桌面端 / 本机运行时，移动端和 Flutter Web 不内置 MCP Server
- 真实桌面 host transport 尚未完成，当前完成 bridge contract / fail-fast / 测试 runtime
- 附件二进制上传体验进入后续 v0.5

## M4：Assets & Import/Export

状态：已完成，最终 release gate 分支：`develop/v0.5.7`。

目标：附件与 CSV 导入导出闭环。

范围：

- asset_create_upload_url
- asset_register_external_url
- memo asset 引用
- 微信 / 支付宝账单导入预览
- 导入提交与批次回滚
- Markdown / CSV / JSON export
- release gate 文档与 smoke 路径

验收：

- 图片或文件可注册为 asset metadata
- 外链可保存并在 UI 展示
- CSV 不直接写正式账单表，导入前可预览
- 微信 / 支付宝账单可解析到 preview rows
- 导入后可按 batch 回滚
- 核心数据可导出
- 服务端非 integration 回归与 Flutter analyze/test 通过

## M5：Import / Export / Asset Experience

状态：规划中，当前分支：`develop/v0.6.0`。

目标：把 v0.5 的附件、导入、回滚和导出 API 闭环做成 Flutter 客户端可用体验。

范围：

- Flutter 导入入口与文件选择
- 微信 / 支付宝账单预览表格
- 导入提交与二次确认
- 导入批次列表与回滚
- 导出入口与诊断信息
- 附件库基础管理体验

验收：

- 用户可从 Flutter 上传账单并预览
- 用户可查看错误行 / 忽略行 / 重复行
- 用户可确认提交并按 batch 回滚
- 用户可导出 ledger CSV / memo Markdown / all JSON
- 用户可查看附件库基础状态
- Flutter analyze/test 通过
- 服务端非 integration 回归通过

## M6：Windows Local MCP

状态：待规划。

目标：支持本地模型、离线 AI、私有部署。

范围：

- Local MCP stdio
- Desktop Local Core host transport
- 与 Cloud MCP 共用 schema
- 写本地 PowerSync / SQLite
- 联网后同步
