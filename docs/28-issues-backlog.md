# 28. Lifly AI-Native Issues Backlog

本文档是 Lifly 的版本化 Issue 种子清单。每个 Issue 都应包含目标、范围、禁止事项、验收标准和相关文档。

## 已完成版本族

### v0.1 Foundation / Governance

- LC-0000 Rename and align project as Lifly
- LC-0001 Add v0.1 architecture freeze docs
- LC-0002 Establish AI execution governance

### v0.2 Local Data

- LC-0101 Local memo CRUD
- LC-0102 Local expense CRUD
- LC-0103 Local task CRUD
- LC-0104 Local asset metadata

### v0.3 Cloud Sync

- LC-0201 PowerSync integration spike
- LC-0202 Audit log write path
- LC-0203 Trash state machine

### v0.4 AI Write / MCP

状态：已完成，最终 tag：`v0.4.11`。

- LC-0401 Define Cloud / Local MCP shared protocol schema
- LC-0402 Implement Cloud MCP direct memo / expense / task / asset writes
- LC-0403 Implement capture_parse / capture_commit / capture_undo persistence
- LC-0404 Harden mcp_undo_actions and ai_trashed state
- LC-0405 Add Flutter AI Capture parse / commit / undo entry
- LC-0406 Add AI audit diagnostics and safety boundaries
- LC-0407 Add Cloud / Local MCP parity tests and v0.4 release gate

### v0.5 Assets & Import/Export

状态：已完成，发布门禁记录见 `docs/64-v0.5-release-gate.md`。

### LC-0501 Asset metadata and upload intent hardening

目标：让内部文件上传记录、外部链接注册、asset metadata 状态和审计路径稳定。

验收：

- `asset_create_upload_url` 返回稳定 asset metadata
- `asset_register_external_url` 支持 link / embed
- asset 写入进入 audit_logs
- 删除/撤销只进入状态机，不物理删除

### LC-0502 Flutter asset reference UI

目标：让 memo / detail 页面可展示 asset 引用和外部链接。

验收：

- 备忘详情可展示关联 asset
- 外链可点击或复制
- 附件错误状态可诊断

### LC-0503 Generic CSV import preview

目标：实现通用 CSV 导入预览，不直接写正式业务表。

验收：

- 上传 CSV 后生成 preview rows
- 可显示字段映射和错误行
- 不确认时不写正式账单 / 备忘 / 任务表

### LC-0504 Alipay / WeChat bill parser hardening

目标：强化支付宝 / 微信账单 CSV 解析。

验收：

- 能识别金额、方向、商户、时间、备注
- 异常行进入 failed rows
- 解析结果可进入 import preview

### LC-0505 Import commit and rollback

目标：导入批次可确认提交，并可按 batch 回滚。

验收：

- commit 后写入正式表
- 每条导入写 audit_logs
- rollback 不物理删除，进入状态机

### LC-0506 Export baseline

目标：提供基础 Markdown / CSV / JSON 导出能力。

验收：

- memo 可导出 Markdown
- ledger 可导出 CSV
- 核心数据可导出 JSON
- 导出操作可诊断，不泄露不必要敏感字段

### LC-0507 v0.5 release gate

目标：建立 v0.5 附件与导入导出全量回归入口。

验收：

- API tests 通过
- Flutter analyze/test 通过
- import/export smoke 通过
- 文档、roadmap、milestones、backlog 同步更新

## 下一阶段：v0.6 Import / Export / Asset Experience

状态：规划中，计划文件见 `docs/development-plans/v0.6.0-import-export-experience.md`。

### LC-0601 Flutter import/export repository

目标：封装导入预览、提交、回滚、批次查询和导出 API，提供稳定 DTO 与 repository tests。

### LC-0602 Flutter import entry and file picker

目标：提供微信 / 支付宝账单选择、上传、provider=auto 和上传失败诊断。

### LC-0603 Flutter import preview UI

目标：提供预览表格、状态筛选、错误行 / 忽略行展示和分页读取。

### LC-0604 Flutter import commit and batch list

目标：提供提交二次确认、提交结果展示、导入批次列表和批次详情。

### LC-0605 Flutter import rollback UI

目标：提供批次回滚二次确认、回滚结果展示和重复回滚错误展示。

### LC-0606 Flutter export UI

目标：提供 memo Markdown、ledger CSV、tasks/assets/all JSON 的导出入口和诊断信息。

### LC-0607 Flutter asset library polish

目标：补齐附件库检索、状态展示、外链复制和 memo 引用体验。

### LC-0608 v0.6 release gate

目标：完成 v0.6 UI 体验层自动回归、手动 smoke 和文档收口。
