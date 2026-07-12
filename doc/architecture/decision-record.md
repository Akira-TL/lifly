# Lifly v0.1 已确认决策记录

## 1. 产品定位

Lifly 是一个 AI-first / Chat-first 的个人生活数据系统。当前阶段以个人自用为起点，后续可能商业化。架构按可开源、可私有部署、可商业化云服务的方式设计。

## 2. 第一版入口

第一版同时支持 App 手动记录和 AI/MCP 记录。App 是查看、修正、导入导出和离线记录入口；AI/MCP 是核心记录入口。

## 3. 平台范围

MVP 优先支持 Windows 与 Android。架构预留 macOS、iOS、Linux 与 Web。

## 4. 技术栈

- 客户端：Flutter
- 后端：FastAPI + PostgreSQL
- 同步：PowerSync
- MCP：TypeScript，Cloud MCP + Windows Local MCP
- 附件：对象存储，数据库只保存 metadata

## 5. MVP 模块

MVP 只做：

- 备忘录 / 日记 / 文档
- 记账
- 任务提醒
- 附件
- CSV 导入
- 审计日志
- 回收站 / Tombstone

## 6. 明确不做

v0.1 不做：

- 完整日历 UI
- 多用户/家庭账本
- Android 通知监听
- 飞书/Notion 双向同步
- 完整复式记账
- 端到端加密
- 社交功能
- 团队协作
- 复杂块编辑器

## 7. AI 写入原则

AI 不能直接操作数据库。所有 AI 写入必须通过 MCP/API，并写入 audit log。AI 删除不能真删，只能进入 AI 回收站。

## 8. 删除原则

用户删除进入普通回收站，后续清理时保留 tombstone。AI 删除进入 ai_trashed，等待用户确认。
