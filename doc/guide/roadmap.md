# 路线图

本文档只记录长期产品和工程路线，不再承载单轮开发计划。已完成的临时计划应迁移到对应正式文档后删除。

## 1. 当前能力基线

Lifly 当前核心底座：

```text
备忘 / 记账 / 任务
AI Capture parse / commit / undo
附件与外链
导入导出
审计 / 回收站 / 撤销
本地优先 / 云端同步
Flutter 客户端真实 API 接入
跨端 Theme Runtime、Lifly Core、主题包缓存与 Core-first Web 启动
Web 极简 Shell、全局管理中心、共享页面状态与导航持久化
```

## 2. 近期路线：Web UI/UX 与真实数据消费

v0.7.0 已完成产品数据地基，v0.8.0 已完成跨端主题应用框架，v0.8.1 已完成 Web 极简 Shell 与全局导航。下一阶段进入 Web 首页真实数据消费，页面必须继续使用既有 read model，不回退到假数据和纯视觉原型。

```text
Web 极简 Shell 与全局导航（v0.8.1 已完成）
Web 首页注意力分发与真实 Home Overview 消费（下一阶段）
Web 备忘高密度列表、AI 分类与标签消费
Web 记账预算、分类占比和洞察消费
Web 任务预警与提醒策略消费
Web AI、附件、导入导出、搜索和诊断体验
多端响应式与发布门禁
```

验收原则：

```text
客户端不写死预算、分类占比、消费洞察、AI 分类状态、任务预警策略
页面正常优先消费云端拉取和同步后的正式字段，云端失败或断网时消费 Local Core / PowerSync 本地 read model
云端 API 是正常读取和同步入口，本地 read model 是失败兜底和离线可用保障
手机端、Web、桌面端共享业务契约，但布局可以不同
```

## 3. Phase 0：架构封板

目标：

- 文档完成；
- 技术选型确认；
- 数据模型确认；
- MCP tool schema 确认；
- 原型页面确认。

产物：

- 正式文档；
- monorepo；
- Docker Compose；
- schema 草案。

## 4. Phase 1：本地记录闭环

目标：

- Flutter 客户端；
- 本地 SQLite / Local Core；
- 备忘录；
- 记账；
- 任务；
- 附件 metadata；
- 基础 UI。

验收：

- 无网可新建数据；
- 本地搜索可用；
- 基础编辑稳定。

## 5. Phase 2：云端同步

目标：

- 登录；
- PostgreSQL；
- PowerSync；
- 跨设备同步；
- 同步状态 UI；
- 删除状态机。

验收：

- 一个端创建，其他端可见；
- 离线创建，联网后可同步；
- 删除状态同步正确。

## 6. Phase 3：附件系统

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

## 7. Phase 4：MCP 与 AI

目标：

- Cloud MCP；
- capture_parse；
- capture_commit；
- capture_undo；
- 混合输入；
- audit log；
- Windows Local MCP。

验收：

- AI/MCP 可创建备忘、账单、任务；
- 混合输入可拆分；
- AI 写入可审计、可撤销；
- 本地 MCP 可离线写入。

## 8. Phase 5：导入导出

目标：

- 通用 CSV；
- 支付宝账单；
- 微信账单；
- 导入预览；
- 批次回滚；
- 导出 CSV/Markdown/JSON。

验收：

- 导入不直接写正式账单；
- 可重复导入检测；
- 批次可回滚；
- 数据可导出。

## 9. Phase 6：产品体验地基

目标：

- 首页今日关注 read model；
- 预算和分类统计；
- 消费洞察；
- 备忘 AI 分类；
- 任务 AI 预警策略；
- 聊天式 AI Capture；
- 手机端核心导航重构。

验收：

- 首页能基于本地数据展示真实 attention_items 和 recent_activity；
- 预算、分类占比、消费洞察优先来自本地 read model；
- AI 分类状态来自可同步的结构化模型；
- 任务预警来自可同步的策略模型；
- 云端 API 与本地 read model 字段同构；
- 手机端底部导航为 5 个入口。

## 10. Phase 7：跨端主题应用框架

状态：已完成。

目标：

- Lifly Core 极简默认主题；
- 声明式 Theme Manifest 与 Semantic Tokens；
- Web、手机端、桌面端共享 Theme Runtime；
- 主题选择和色彩模式；
- 平台 Profile 与受控布局；
- 版本缓存、完整性、授权占位、回滚与 fallback；
- Web Core-first 启动；
- 默认 Web / Wasm 构建门禁。

验收：

- 默认 Core 不等待网络、同步、授权或缓存；
- 主题失败最终降级 Core；
- 新增主题不修改业务页面；
- 远程主题不执行任意代码；
- 复杂主题不能放宽 Core 性能预算。

## 11. Phase 8：Web 极简 Shell 与全局导航

状态：已完成。

目标：

- Web dashboard 侧栏与五核心入口；
- 搜索、快速记录和单一管理中心；
- 当前核心入口和侧栏折叠本地持久化；
- Loading / Empty / Error / Offline 共享页面状态；
- 键盘、可访问性、默认 Web 与 Wasm 发布门禁。

验收：

- 管理页返回和主题切换保持当前核心页与服务实例；
- 浏览器刷新后恢复合法核心入口；
- 文本输入聚焦时全局快捷键让路；
- Web dashboard、桌面 compact 和手机五入口无回归；
- `scripts/check-v0.8.1-release-gate.sh` 可重复运行。

## 12. Phase 9：第三方生态

目标：

- 飞书导入；
- Notion 导入；
- Obsidian 导入；
- ICS 导入/导出；
- 机器人模板；
- 插件机制。

## 13. Phase 10：商业化准备

目标：

- 云服务套餐；
- 容量限制；
- 账单系统；
- 隐私政策；
- 数据删除流程；
- 监控与告警；
- 服务稳定性。
