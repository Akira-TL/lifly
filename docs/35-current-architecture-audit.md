# 35. Lifly 当前架构审计报告

关联 Issue：#3 `[LC-0002] Audit current code against Lifly v0.1 architecture freeze`

审计分支：`agent/m0-architecture-audit`

审计目标：检查当前远程 `master` 的实现是否与 `docs/26-v0.1-architecture-freeze.md` 对齐，并输出后续开发前必须处理的差异清单。

> 本报告只做审计，不修改运行时代码。

---

## 1. 总体结论

当前 Lifly 仓库已经超过“空骨架”状态，处于 **M0 已启动、M1/M3 部分提前实现** 的阶段。

已基本对齐 v0.1 架构冻结的部分：

- 项目命名已从 LifeCore / lifecore / Lifily 大部分统一为 Lifly / lifly。
- FastAPI 主应用已存在，并提供 `/api/v1/health`。
- 后端已经挂载 memo、ledger、task、asset、mcp、trash、import/export、search、plugin 等 router。
- Cloud MCP 已挂载，并且第一版工具清单基本已经在 Python FastMCP 层实现。
- 数据模型已经包含 Memo、Asset、Ledger、Task、Reminder、CalendarEvent、ImportBatch、ImportRow、AuditLog、Tombstone、User、ApiToken。
- 附件模型采用 metadata + object storage key / external URL 的方向，没有把二进制文件放进 PostgreSQL。
- CSV 导入模型采用 `import_batches` + `import_rows`，符合“导入先预览、再 commit”的冻结边界。
- MCP 创建 memo / expense / task 的路径已经写入 audit log。
- `capture_undo` 会将实体移入 `ai_trashed`，符合 AI 删除不直接物理删除的方向。

主要差异和风险：

- Cloud MCP 服务名仍有 `lifily-cloud` / `Lifily Cloud MCP` 拼写残留，应改成 `lifly-cloud` / `Lifly Cloud MCP`。
- 第一版 MCP tool schema 已在 Python `services/api/app/modules/mcp/cloud_server.py` 中隐式存在，但尚未抽象到冻结文档要求的 `packages/protocol`。
- 当前 Cloud MCP 和 internal API 都在 Python 后端内，尚未形成冻结文档中的 TypeScript Cloud MCP 服务边界。
- MCP 内部写入仍使用固定 `user_id="local-dev"`，后续必须接入真实 auth/token user context。
- Asset 创建、更新、删除路径目前没有统一写 audit log，和“所有创建、修改、删除、导入、导出、MCP 写操作必须写 audit_logs”的冻结要求不完全一致。
- FastAPI 启动时使用 `Base.metadata.create_all` 自动建表，适合 M0/M1 验证，但后续需要 Alembic migration。
- PowerSync 在 Docker Compose 中仍是占位服务，尚未完成同步规则和客户端集成。
- Local MCP 还没有实现；当前只看到 Cloud MCP 入口。
- Flutter 客户端未在本次审计中深入检查，需由 Client Agent 单独验证。

---

## 2. 架构冻结项对照

### 2.1 产品范围

冻结文档要求 v0.1 只做：

- 备忘录 / 日记 / 文档
- 记账
- 任务提醒
- 附件
- CSV 导入
- Cloud MCP
- Windows Local MCP
- 本地离线
- 云端同步
- 审计与回收站

当前代码覆盖度：

| 模块 | 当前状态 | 结论 |
|---|---|---|
| 备忘录 / 日记 / 文档 | `Memo` 模型存在，支持 `type`、Markdown、tags、mood | 基本对齐 |
| 记账 | `LedgerAccount`、`LedgerCategory`、`LedgerTransaction`、`LedgerEntry` 存在 | 基本对齐 |
| 任务提醒 | `Task`、`Reminder` 存在 | 基本对齐 |
| 附件 | `Asset`、`MemoAssetRef`、上传 URL、外部 URL 注册存在 | 基本对齐，但 audit 不完整 |
| CSV 导入 | `ImportBatch`、`ImportRow` 存在 | 模型对齐，流程需继续验证 |
| Cloud MCP | FastMCP server 已存在并挂载 | 功能提前实现，但边界需收敛 |
| Windows Local MCP | 暂未看到实现 | 未完成 |
| 本地离线 | 后端不负责，客户端需审计 | 未确认 |
| 云端同步 | PowerSync compose 占位 | 未完成 |
| 审计与回收站 | `AuditLog`、`Tombstone`、trash/mcp undo 路径存在 | 部分对齐 |

未发现明显实现冻结文档中明确禁止的功能，如 Android 通知监听、社交、多用户协作、复杂块编辑器等。

---

### 2.2 技术栈

冻结要求：

- Client：Flutter，Windows + Android first
- Backend：FastAPI + PostgreSQL
- Sync：PowerSync
- MCP：TypeScript，Cloud MCP 使用 HTTP，Local MCP 使用 stdio
- Assets：对象存储，PostgreSQL 只保存 metadata
- Monorepo：pnpm workspace + uv + Flutter 独立工程

当前状态：

| 技术项 | 当前状态 | 审计结论 |
|---|---|---|
| FastAPI | 已存在 | 对齐 |
| PostgreSQL | docker-compose 和 config 已对齐 lifly 命名 | 对齐 |
| pnpm workspace | 根 `package.json` 和 `pnpm-workspace.yaml` 存在 | 对齐 |
| uv | `services/api` 使用 uv 路线 | 对齐 |
| Flutter | 需要 Client Agent 后续验证 | 未审计 |
| PowerSync | Docker Compose 有占位服务 | 未完成 |
| Cloud MCP TypeScript | 当前为 Python FastMCP 内嵌实现 | 与冻结目标存在差异 |
| Local MCP stdio | 暂未看到实现 | 未完成 |
| Object Storage | MinIO 配置和 asset metadata 存在 | 基本对齐 |

结论：后端与 infra 已经满足 M0 验证需求；MCP 技术边界需要后续 ADR 或 Issue 明确，是继续 Python FastMCP 过渡，还是迁移/抽象到 TypeScript Cloud MCP。

---

## 3. 数据模型审计

### 3.1 Memo

当前 `Memo` 已包含：

- `user_id`
- `type`
- `title`
- `content_markdown`
- `tags`
- `mood`
- `source_capture_id`
- `status`
- `source`
- `revision`
- `deleted_at`

结论：与 memo / journal / clip / doc 的 v0.1 方向基本一致。

### 3.2 Asset

当前 `Asset` 已包含：

- `kind`：internal / external
- `asset_type`
- `filename`
- `mime_type`
- `size_bytes`
- `sha256`
- `storage_provider`
- `storage_key`
- `external_url`
- `external_provider`
- `visibility`
- `sync_status`
- `status`

结论：附件模型方向正确。

风险：`storage_key` 当前会返回给 API 调用方。后续产品化时应避免客户端长期依赖真实 storage key，只暴露 `asset_id` 和短期 upload/download URL。

### 3.3 Ledger

当前记账模型包括：

- `LedgerAccount`
- `LedgerCategory`
- `LedgerTransaction`
- `LedgerEntry`

结论：符合“第一版简化流水，底层预留类复式”的决策。

### 3.4 Task / Reminder / CalendarEvent

当前已经存在：

- `Task`
- `Reminder`
- `CalendarEvent`

结论：符合“第一版做任务提醒，底层预留 calendar_events，但不做完整日历 UI”的决策。

### 3.5 Import

当前已经存在：

- `ImportBatch`
- `ImportRow`

结论：符合 CSV 导入必须先进入批次和预览层的架构边界。

### 3.6 Audit / Tombstone

当前已经存在：

- `AuditLog`
- `Tombstone`

结论：基础模型对齐。

风险：模型存在不代表所有写路径都已写 audit log。MCP 主要写路径已写 audit，但 assets、imports、普通 REST CRUD 等还需要逐项补齐。

---

## 4. MCP 审计

冻结文档列出的第一版 MCP tool 清单：

```text
capture_parse
capture_commit
capture_undo
memo_create
memo_search
expense_create
expense_search
expense_summary
task_create
task_list
task_complete
asset_create_upload_url
asset_register_external_url
```

当前 `services/api/app/modules/mcp/cloud_server.py` 已实现同名工具，并通过内部 HTTP 调用 `/api/v1/mcp/*` 与 `/api/v1/assets/*`。

结论：MCP 工具覆盖度高，甚至已经提前接近 M3。

但存在三个架构风险：

1. 工具 schema 目前隐式分散在 Python 函数签名中，未进入 `packages/protocol`。
2. Cloud MCP 当前不是独立 TypeScript 服务，而是 Python FastMCP 内嵌到 API。
3. 服务名仍有 `lifily-cloud` / `Lifily Cloud MCP` 拼写残留。

建议：

- #4 不应从零发明 tool schema，而应以当前 Python FastMCP 实现为输入，反向抽象出 `packages/protocol`。
- 短期可以保留 Python FastMCP 作为 M0/M1/M3 验证实现，但必须创建 ADR 说明“Python 内嵌 MCP 是过渡实现还是正式实现”。
- 立即创建一个小修复 Issue，统一 `lifily-cloud` 拼写。

---

## 5. 审计日志与删除状态

### 5.1 MCP 写入路径

当前 MCP 写入路径中，以下操作已经写 audit log：

- `capture_commit` 创建 memo / ledger_transaction / task
- `capture_undo`
- `memo_create`
- `expense_create`
- `task_create`
- `task_complete`

结论：MCP 关键写路径基本符合冻结要求。

### 5.2 Asset 路径

当前 asset 路径包括：

- create upload URL
- register external URL
- upload complete
- update asset
- delete asset

但这些路径暂未看到统一写 audit log。

结论：需要补齐。

### 5.3 删除状态

`capture_undo` 会将实体状态设为 `ai_trashed`，并更新 `deleted_at` / `revision`，符合 AI 删除不直接物理删除的方向。

Asset 删除当前将 `status` 设为 `deleted`，而不是 `user_trashed` / `ai_trashed` / `purged`，需要与统一删除状态机对齐。

---

## 6. 本地启动与基础设施

当前本地验证已通过：

```json
{"status":"ok","version":"0.7.0","port":8310}
```

当前 `docker-compose.yml` 已统一 lifly 命名，并提供：

- PostgreSQL：host `8332`
- Redis：host `8379`
- MinIO：host `8300` / console `8301`
- PowerSync：profile `powersync`，host `8380`

结论：M0 的本地基础设施已具备继续开发条件。

风险：PowerSync 仍为占位，需要单独 spike 验证。

---

## 7. 风险分级

### P0：继续开发前必须处理或明确

1. `packages/protocol` 缺失 MCP schema，#4 必须优先执行。
2. Cloud MCP 技术边界与冻结文档不完全一致：当前是 Python FastMCP 内嵌，不是独立 TypeScript Cloud MCP。
3. 写操作 audit log 未全覆盖，尤其 asset/import/普通 REST CRUD。
4. 固定 `user_id="local-dev"` 只能作为 M0 开发占位，不能进入真实多端同步/云端使用。

### P1：M1/M2 前处理

1. `Base.metadata.create_all` 应替换或补充为 Alembic migration。
2. PowerSync 需要真实配置和同步规则。
3. Asset 删除状态应统一进入 trash 状态机。
4. `storage_key` 不应作为长期客户端接口暴露。

### P2：后续优化

1. CORS 当前允许 `*`，MVP 开发可接受，后续需要环境化。
2. Cloud MCP root mount 仍是 catch-all，需要保证所有 API route 都在 mount 前声明；长期可考虑把 MCP endpoint 移到显式路径。
3. FastMCP 服务名拼写应立即修复。

---

## 8. 建议后续 Issue

### LC-0004 Fix Lifly Cloud MCP naming leftovers

目标：修复 `services/api/app/modules/mcp/cloud_server.py` 中的 `lifily-cloud` 和 `Lifily Cloud MCP` 拼写。

范围：

- `services/api/app/modules/mcp/cloud_server.py`

验收：

- 服务名为 `lifly-cloud`
- instructions 中显示 `Lifly Cloud MCP`
- 不修改 tool schema
- 不修改业务逻辑

---

### LC-0005 Define packages/protocol MCP schema v0.1

目标：以当前 Python FastMCP 工具为基准，在 `packages/protocol` 中定义第一版 MCP tool schema。

范围：

- `packages/protocol/**`
- `docs/08-mcp-design.md`

验收：

- 所有冻结工具均有 schema
- schema 有基础 contract tests
- 不做业务持久化
- 不修改后端 router 行为

---

### LC-0006 Add audit log coverage for assets module

目标：补齐 asset create / update / delete / upload-complete 的 audit log。

范围：

- `services/api/app/modules/assets/router.py`
- 相关测试

验收：

- create upload URL 写 audit log
- register external URL 写 audit log
- upload complete 写 audit log
- update asset 写 audit log
- delete asset 写 audit log

---

### LC-0007 ADR: Decide Cloud MCP implementation boundary

目标：决定 Cloud MCP 是否继续使用 Python FastMCP 内嵌实现，还是迁移/并行到 TypeScript Cloud MCP。

候选方案：

- A. 短期保留 Python FastMCP，TypeScript 只做 schema package。
- B. 迁移到独立 TypeScript Cloud MCP 服务。
- C. Python FastMCP 作为内部 dev server，生产使用 TypeScript Cloud MCP。

建议：先采用 A，等 schema 和 memo_create 最小闭环稳定后再评估 B/C。

---

### LC-0008 PowerSync integration spike

目标：验证 PostgreSQL ↔ PowerSync ↔ 客户端 SQLite 的同步链路。

范围：

- `infra/powersync/**`
- `services/api/**` 必要配置
- `apps/client_flutter/**` 最小客户端验证

验收：

- Windows/Android 任一客户端本地写 memo
- PostgreSQL 可同步看到
- 离线写入后联网可同步

---

## 9. 下一步执行建议

建议按以下顺序继续：

```text
1. 合并本审计报告 PR
2. 关闭 #3
3. 创建并执行 LC-0004：修复 Lifly Cloud MCP 拼写残留
4. 执行 #4：定义 packages/protocol MCP schema v0.1
5. 创建 ADR：确认 Cloud MCP 技术边界
6. 做 memo_create 最小闭环 contract test
7. 做 asset audit log 补齐
8. 做 PowerSync spike
```

当前最重要的判断：

> Lifly 现在已经具备继续开发条件，但必须先把 MCP schema 抽象出来，并明确 Cloud MCP 的技术边界。否则后续 AI agent 会继续在 Python、TypeScript、文档三套协议之间发散。
