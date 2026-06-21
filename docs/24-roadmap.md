# 24. 路线图

## Phase 0：架构封板

目标：

- 文档完成；
- 技术选型确认；
- 数据模型确认；
- MCP tool schema 确认；
- 原型页面确认。

产物：

- docs；
- monorepo；
- Docker Compose；
- schema 草案。

## Phase 1：本地 MVP

目标：

- Flutter Windows/Android；
- 本地 SQLite；
- 备忘录；
- 记账；
- 任务；
- 附件 metadata；
- 基础 UI。

验收：

- 无网可新建数据；
- 本地搜索可用；
- 基础编辑稳定。

## Phase 2：云端同步

目标：

- 登录；
- PostgreSQL；
- PowerSync；
- 跨设备同步；
- 同步状态 UI；
- 删除状态机。

验收：

- Windows 创建，Android 可见；
- Android 离线创建，联网后 Windows 可见；
- 删除状态同步正确。

## Phase 3：附件系统

目标：

- 对象存储；
- 上传 URL；
- 图片上传；
- 文件卡片；
- 外链注册；
- 本地缓存。

验收：

- 图片可上传并引用；
- 外链可保存；
- 缓存可清理；
- 附件丢失不影响正文。

## Phase 4：MCP 与 AI

目标：

- Cloud MCP；
- capture_parse；
- capture_commit；
- 混合输入；
- audit log；
- undo；
- Windows Local MCP。

验收：

- Hermes/OpenClaw 可创建备忘/账单/任务；
- 混合输入可拆分；
- AI 删除进 AI 回收站；
- 本地 MCP 可离线写入。

## Phase 5：导入导出

目标：

- 通用 CSV；
- 支付宝 CSV；
- 微信 CSV；
- 导入预览；
- 批次回滚；
- 导出 CSV/Markdown/JSON。

验收：

- 导入不直接写正式账单；
- 可重复导入检测；
- 批次可回滚；
- 数据可导出。

## Phase 6：体验完善

目标：

- 更好的首页；
- 搜索增强；
- 图表统计；
- 附件预览增强；
- 提醒系统增强；
- 数据备份。

## Phase 7：第三方生态

目标：

- 飞书导入；
- Notion 导入；
- Obsidian 导入；
- ICS 导入/导出；
- 机器人模板；
- 插件机制。

## Phase 8：商业化准备

目标：

- 云服务套餐；
- 容量限制；
- 账单系统；
- 隐私政策；
- 数据删除流程；
- 监控与告警；
- 服务稳定性。
