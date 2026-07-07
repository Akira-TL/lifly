# MVP 范围与阶段计划

## 1. MVP 目标

MVP 目标是验证 Lifly 的核心闭环：

```text
手动记录 + AI/MCP 记录 + 本地离线 + 云端同步 + 审计可撤销
```

## 2. MVP 平台

必须完成：

- Windows 客户端；
- Android 客户端；
- 云端后端；
- 云端 MCP；
- Windows 本地 MCP。

暂不完成：

- macOS；
- iOS；
- Linux；
- Web 正式版。

## 3. MVP 模块

### 3.1 备忘录

必须支持：

- Markdown 文本；
- memo/journal/clip/doc 分类；
- 标签；
- 附件引用；
- 搜索；
- 本地离线；
- 同步；
- AI 创建。

### 3.2 记账

必须支持：

- 手动记账；
- 自然语言记账；
- 金额、分类、商户、账户、时间、备注；
- 通用 CSV 导入；
- 支付宝 CSV 导入；
- 微信 CSV 导入；
- 导入预览；
- 批次回滚；
- 重复检测；
- 基础统计。

### 3.3 任务提醒

必须支持：

- 创建任务；
- 设置提醒时间；
- 完成任务；
- 今日任务列表；
- 逾期任务；
- AI 创建任务；
- 任务审计与撤销。

## 4. MVP MCP 工具

第一版 MCP 工具控制在少量稳定工具：

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

## 5. MVP 里程碑

### M0：项目初始化

- monorepo 初始化；
- Flutter 工程初始化；
- FastAPI 工程初始化；
- MCP Server 工程初始化；
- 数据模型草案；
- Docker Compose 开发环境。

### M1：本地记录闭环

- Windows/Android 本地 SQLite；
- 备忘录 CRUD；
- 记账 CRUD；
- 任务 CRUD；
- 附件 metadata；
- 基础 UI。

### M2：云端与同步

- 用户登录；
- PostgreSQL；
- PowerSync；
- Windows/Android 数据同步；
- 删除与 tombstone；
- 基础冲突处理。

### M3：附件系统

- 内部附件上传；
- 外部链接注册；
- 本地缓存；
- 图片预览；
- 文件卡片；
- 对象存储接入。

### M4：MCP 与 AI

- 云端 MCP；
- capture_parse；
- capture_commit；
- 混合输入；
- 审计日志；
- AI 回收站；
- Windows 本地 MCP。

### M5：导入导出

- 通用 CSV；
- 支付宝账单；
- 微信账单；
- 导入预览；
- 批次回滚；
- 账单导出；
- 备忘录导出 Markdown。

## 6. 发布准入条件

MVP 可以发布前必须满足：

- 离线写入不丢数据；
- 同步失败可重试；
- 所有 MCP 写操作有 audit log；
- AI 删除不会真删；
- CSV 导入可回滚；
- 附件上传失败不影响正文保存；
- Windows 和 Android 基础体验稳定。
