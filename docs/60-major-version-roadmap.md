# 60. Lifly 大版本开发路线图

## 1. 文档目的

本文档用于规划 Lifly 从已完成的 `v0.1.0` 工程基线到个人生产可用版本 `v1.0.0` 的大版本开发内容。

`docs/59-version-control-plan.md` 更偏版本号、分支、tag、release gate 规则；本文档更偏每个大版本的产品目标、工程边界、验收标准和推荐 Issue 切片。

当前判断：

```text
当前稳定版本：v0.5.6
当前开发入口：v0.5.7 release gate / v0.6.0 UI 体验层规划
近期重点：完成 v0.5 发布门禁收口，并规划 Flutter 导入导出 UI
```

## 2. 总体路线

Lifly 的版本推进不按页面数量拆分，而按“数据闭环能力”拆分。

核心顺序：

```text
v0.1.0 Foundation Baseline
  ↓
v0.2.x Local Data MVP
  ↓
v0.3.0 Cloud Sync MVP
  ↓
v0.4.x AI Write 全量开发
  ↓
v0.5.0 Assets & Import/Export MVP
  ↓
v0.6.0 Private Alpha
  ↓
v0.7.0 Private Beta
  ↓
v1.0.0 Personal Production
```

基本原则：

```text
先本地闭环，再云同步
先手动写入稳定，再 AI 写入扩展
先结构化数据稳定，再附件和导入导出
先个人自用稳定，再考虑邀请测试和商业化
```

---

## 3. v0.1.0 Foundation Baseline

### 3.1 版本定位

`v0.1.0` 是 Lifly 的第一个工程基线版本。它不追求完整可用，而是确保代码库、文档、协议、测试、命名和模块边界稳定，后续 AI agent 可以在统一规则下继续开发。

### 3.2 当前已具备

```text
pnpm monorepo
Flutter client
FastAPI backend
MCP v0.1 protocol schema
Cloud MCP runtime
Local MCP stdio skeleton
Local Core fake bridge
Flutter Dart Local Core fake bridge
PowerSync schema 对齐计划
基础 docs / milestones / backlog / agent protocol
```

### 3.3 必须完成

```text
项目命名统一为 Lifly / lifly
pnpm-lock.yaml 入仓
pnpm test 通过
pnpm typecheck 通过
Flutter analyze/test 通过
FastAPI health version 统一为 0.1.0
MCP v0.1 tool schema 稳定
Cloud MCP contract test 通过
版本控制文档和大版本路线图入仓
```

### 3.4 明确不做

```text
真实本地持久化
真实 PowerSync uploadData
跨端同步
生产级 auth
Local MCP 调用 Flutter/Dart 真实数据层
附件完整上传体验
导入导出完整 UI
```

### 3.5 Release Gate

```text
pnpm test
pnpm typecheck
cd apps/client_flutter && flutter analyze
cd apps/client_flutter && flutter test
cd services/api && uv run --group dev pytest tests/integration/test_mcp_v0_1_contract.py
git diff --check
```

### 3.6 推荐 Issue

```text
LC-0101 Finish v0.1 release gate
LC-0102 Verify Lifly naming consistency
LC-0103 Stabilize workspace lockfile and CI cache
LC-0104 Update docs index and release checklist
```

---

## 4. v0.2.x Local Data MVP

### 4.1 版本定位

`v0.2.x` 的目标是让 Lifly 具备真正的本地优先记录能力。用户即使没有网络，也能在 Flutter 客户端创建、查看、编辑、删除 memo / expense / task，并且应用重启后数据不丢。

这是 Lifly 最关键的底座版本。没有 v0.2.x，就不应该继续扩大 AI 和云同步能力。

### 4.2 核心目标

```text
Flutter/Dart 拥有 PowerSyncDatabase
Dart Local Core Bridge 写真实本地表
memo 本地 CRUD 闭环
task 本地 CRUD / complete 闭环
ledger expense 本地 create/search/summary 闭环
所有本地写入写 audit_logs
所有本地写入维护 revision / updated_at / source
删除只做 soft delete，不物理删除
```

### 4.3 工程内容

#### Local Core

```text
实现 PowerSyncLocalCoreBridge
定义 LocalCoreRepository 层
统一 LocalCoreContext
统一 id / timestamp / revision 生成
统一 audit log writer
统一 soft delete writer
```

#### Flutter UI

```text
memo 页面接入 Local Core
task 页面接入 Local Core
ledger 页面接入 Local Core
settings 页面显示当前数据模式
local diagnostics 执行本地写入 smoke
空状态 / 错误状态 / loading 状态稳定
```

#### 数据层

```text
启用 memos / tasks / ledger_transactions 本地写入
启用 audit_logs 本地写入
启用 mcp_undo_actions 表结构预留
启用 tombstones 表结构预留
确认 assets metadata 表结构可迁移但暂不强做 UI
```

### 4.4 明确不做

```text
不做跨端同步
不做 cloud uploadData
不做完整 conflict resolution
不做 Local MCP 真实桥接
不做附件二进制上传
不做生产级加密
```

### 4.5 验收标准

```text
断网时可创建 memo / expense / task
应用重启后数据不丢
memo / task / expense 列表可从本地数据读取
本地完成 task 后状态持久化
删除后进入非 active 状态而不是物理删除
每次写入都有 audit_logs 记录
Flutter local core tests 覆盖主要路径
```

### 4.6 修订号规划

详细计划见：

```text
docs/development-plans/v0.2.0-local-data-mvp.md
```

当前 v0.2.x 修订号拆分：

```text
0.2.0 版本规划与本地数据边界冻结
0.2.1 PowerSync Local Core 基础底座
0.2.2 audit_logs 与本地写入公共工具
0.2.3 memo 本地 CRUD 闭环
0.2.4 task 本地 CRUD / complete 闭环
0.2.5 expense 本地 create/search/summary 闭环
0.2.6 Flutter 页面切换到 Local Core 模式
0.2.7 本地持久化回归与重启验证
0.2.8 v0.2 release gate 与文档收口
```

---

## 5. v0.3.0 Cloud Sync MVP

### 5.1 版本定位

`v0.3.0` 的目标是让本地数据能够同步到云端，并在 Windows 与 Android 之间形成最小跨端闭环。

这个版本解决 Lifly 的第二个核心问题：数据不只存在本机，而是可以跨设备延续。

### 5.2 核心目标

```text
PowerSync uploadData 可用
后端接收本地 CRUD 写入
PostgreSQL schema 与 Flutter PowerSync schema 对齐
Windows 创建的数据 Android 可见
Android 离线创建的数据联网后 Windows 可见
删除/恢复状态跨端一致
同步状态可诊断
```

### 5.3 工程内容

#### Backend

```text
新增/整理 sync write endpoints
后端写入 audit_logs
后端处理 revision / updated_at
后端处理 soft delete / tombstones
后端从 create_all 逐步转向 migration 策略
```

#### PowerSync

```text
配置 sync rules
实现 uploadData batch 映射
处理 create/update/delete CRUD op
处理失败重试
处理基础幂等
```

#### Flutter

```text
登录/token 接入最小版本
同步连接状态 UI
同步错误诊断 UI
手动触发 reconnect / resync
本地数据和云端数据一致性 smoke
```

### 5.4 明确不做

```text
不做复杂冲突合并 UI
不做多人协作
不做家庭账本
不做端到端加密
不做高级增量备份
```

### 5.5 验收标准

```text
Windows 创建 memo，Android 可见
Android 离线创建 task，联网后 Windows 可见
expense 跨端汇总一致
删除状态跨端一致
重复上传不会产生重复实体
同步失败有可读错误
CI 或 smoke 覆盖最小同步链路
```

### 5.6 推荐 Issue

```text
LC-0301 Align backend schema with PowerSync local schema
LC-0302 Implement sync write endpoints for memo/task/ledger
LC-0303 Implement PowerSync uploadData mapping
LC-0304 Add basic auth/token flow for sync
LC-0305 Add sync status UI and diagnostics
LC-0306 Add Windows/Android sync smoke checklist
```

---

## 6. v0.4.x AI Write 全量开发

### 6.1 版本定位

`v0.4.x` 的目标是让 AI 成为 Lifly 的完整一等写入入口。Cloud MCP、Local MCP 和 Flutter AI Capture 需要围绕同一套 tool schema 形成写入、确认、撤销、审计和诊断闭环。

这个版本以后，Lifly 才真正接近“AI-first / Chat-first personal life data system”。

### 6.2 核心目标

状态：已在 `v0.4.11` 收口。

```text
Cloud MCP / Local MCP 复用 packages/protocol
Cloud MCP 完整写入 memo / expense / task / asset ref
Local MCP 桌面 bridge contract 与测试 runtime 已建立
capture_parse / capture_commit / capture_undo 真实闭环
Flutter 提供 AI Capture 输入、确认和撤销入口
AI 写入和撤销全部进入 audit logs
AI undo 进入 ai_trashed
AI 不直接物理删除数据
Cloud / Local MCP parity tests 通过
```

### 6.3 工程内容

#### Protocol

```text
继续维护 packages/protocol 为 MCP schema source of truth
增加 schema contract tests
确保 Cloud MCP / Local MCP tool list 完全一致
```

#### Local MCP

```text
实现 Local MCP 到 Dart Local Core 的 bridge transport
定义 Flutter Desktop 本地 bridge 启动/发现机制
Local MCP 不直接写 SQLite
Local MCP 返回标准 MCP tool result
```

#### Capture Flow

```text
capture_parse 生成候选 actions
capture_commit 写入 memo / expense / task
capture_commit 返回 undo_token
capture_undo soft delete 已创建实体
mcp_undo_actions 持久化
```

### 6.4 明确不做

```text
不做复杂自然语言模型训练
不做自动读取系统通知
不做 Android MCP Server
不做 AI 自动批量删除
不做不经确认的大规模导入
```

### 6.5 验收标准

状态：已通过 `bash scripts/check-v0.4-ai-write.sh` 和用户手动 UI 基本验证。

```text
Cloud MCP 可完整写入 memo / expense / task / asset ref
Local MCP 测试 runtime 可完整写入 memo / expense / task；真实桌面 host transport 留到后续桌面专项
Flutter 可触发 AI 写入、确认和撤销
capture mixed input 可拆成多个 action
capture_commit 可选择部分 action
capture_undo 可追踪并进入 AI trash
所有 AI 写入和撤销都有 audit_logs
Cloud 与 Local tool schema 完全一致
```

### 6.6 推荐 Issue

```text
LC-0401 Define Local MCP to Dart bridge transport
LC-0402 Implement Local MCP real Local Core runtime
LC-0403 Implement local capture_parse/commit/undo persistence
LC-0404 Harden mcp_undo_actions and ai_trashed state
LC-0405 Add Cloud/Local MCP parity tests
LC-0406 Add Hermes/OpenClaw local setup docs
```

---

## 7. v0.5.0 Assets & Import/Export MVP

### 7.1 版本定位

`v0.5.0` 的目标是让 Lifly 支持真实生活数据迁入和附件管理。该版本解决两个问题：资料如何随记录保存，历史账单/备忘如何导入系统。

### 7.2 核心目标

```text
附件 metadata 稳定
内部文件上传 URL 可用
外部链接注册可用
memo 可引用 asset
CSV 导入走 preview / commit
支付宝 / 微信账单 CSV 可解析
导入批次可回滚
核心数据可导出
```

### 7.3 工程内容

#### Asset System

```text
asset_create_upload_url
asset_register_external_url
upload complete
asset update/delete audit log
memo_asset_refs
对象存储 provider 抽象
本地缓存策略初版
```

#### Import System

```text
通用 CSV parser
支付宝 CSV parser
微信 CSV parser
import_batches
import_rows
preview UI
commit to ledger_transactions
batch rollback
重复导入检测
```

#### Export System

```text
memo Markdown export
ledger CSV export
task CSV/JSON export
full JSON export 草案
```

### 7.4 明确不做

```text
不做 Notion/飞书双向同步
不做复杂 OCR
不做自动识别所有银行账单格式
不做大规模文件同步优化
不做协作附件权限
```

### 7.5 验收标准

```text
图片/文件可注册为 asset metadata
外链可保存并在 UI 展示
memo 能展示 asset ref
CSV 导入前必须预览
导入 commit 后生成 ledger transactions
导入 batch 可回滚
导出文件可被用户保存和再次读取
```

### 7.6 推荐 Issue

```text
LC-0501 Complete asset audit log coverage
LC-0502 Implement memo asset refs in Flutter UI
LC-0503 Implement generic CSV import preview UI
LC-0504 Implement Alipay/WeChat CSV parser hardening
LC-0505 Implement import batch commit and rollback
LC-0506 Implement Markdown/CSV/JSON export flows
```

---

## 8. v0.6.0 Private Alpha

### 8.1 版本定位

`v0.6.0` 是个人长期试用版本。目标不是功能数量，而是稳定性和日常可用性。

### 8.2 核心目标

```text
首页体验整理
全局搜索增强
账单基础统计
错误提示和空状态完善
设置页诊断完善
数据备份/恢复初版
日志与崩溃诊断
基础安全加固
```

### 8.3 工程内容

```text
Home dashboard
Recent captures
Today tasks
Monthly expense summary
Global search filters
Diagnostics center
Backup export/import
Error boundary
Structured logging
```

### 8.4 明确不做

```text
不做公开注册
不做付费系统
不做复杂团队功能
不做插件市场
```

### 8.5 验收标准

```text
可连续使用一周不丢数据
核心错误能定位
用户可手动备份数据
首页能看见近期记录和待办
搜索能覆盖 memo / task / expense
```

### 8.6 推荐 Issue

```text
LC-0601 Build home dashboard v1
LC-0602 Add global search filters
LC-0603 Add monthly expense statistics
LC-0604 Add backup and restore flow
LC-0605 Add diagnostics center
LC-0606 Add structured app/backend logging
```

---

## 9. v0.7.0 Private Beta

### 9.1 版本定位

`v0.7.0` 是小范围测试版本。目标是让非开发者也能安装、升级、反馈问题。

### 9.2 核心目标

```text
Windows 安装包
Android 安装包
升级不破坏已有数据
数据库 migration 体系
更完整测试覆盖
隐私政策 / 用户协议草案
基础监控与错误反馈
```

### 9.3 工程内容

```text
Flutter Windows packaging
Flutter Android packaging
Versioned database migrations
Release checklist
Crash/error report collection
Privacy policy draft
User agreement draft
Beta feedback channel
```

### 9.4 明确不做

```text
不做大规模商业发布
不做企业部署
不做多人协作
不做复杂订阅计费
```

### 9.5 验收标准

```text
Windows 可安装使用
Android 可安装使用
从 v0.6.x 升级到 v0.7.0 不丢数据
主要功能有回归测试
用户可提交反馈和日志
```

### 9.6 推荐 Issue

```text
LC-0701 Add migration system
LC-0702 Build Windows installer
LC-0703 Build Android release package
LC-0704 Add release upgrade tests
LC-0705 Draft privacy policy and user agreement
LC-0706 Add beta feedback and log export flow
```

---

## 10. v1.0.0 Personal Production

### 10.1 版本定位

`v1.0.0` 是个人生产可用版本。它代表 Lifly 已经可以作为个人长期数据系统使用，而不仅是技术验证项目。

### 10.2 核心目标

```text
本地记录稳定
云同步稳定
AI 写入稳定
附件和导入导出稳定
审计和回收站稳定
备份恢复可靠
安装升级可靠
文档完整
```

### 10.3 必须具备

```text
memo / journal / doc 可长期使用
task / reminder 可长期使用
ledger expense 可长期使用
Windows / Android 同步稳定
Cloud MCP / Local MCP 写入稳定
AI undo 可追踪
数据删除可恢复
数据可导出
数据可备份
```

### 10.4 明确不做

```text
不强制做商业化
不强制做团队协作
不强制做插件市场
不强制做端到端加密
不强制支持所有第三方平台
```

### 10.5 验收标准

```text
普通用户可安装、记录、查询、同步、备份、恢复
连续使用一个月核心数据不丢失
断网/弱网场景可恢复
AI 写入路径安全可追踪
核心数据可以完整导出
发布包、文档、测试、迁移脚本齐全
```

---

## 11. 每个版本的共同交付物

每个大版本都必须交付：

```text
版本目标文档
Issue 切片
测试清单
迁移说明
用户可见变化说明
已知问题列表
下一版本入口 Issue
```

每个版本结束前必须更新：

```text
docs/59-version-control-plan.md
docs/60-major-version-roadmap.md
docs/27-milestones.md
docs/28-issues-backlog.md
README.md
docs/README.md
```

## 12. 当前最推荐的下一步

当前已经完成 `v0.1.0` Foundation Baseline。下一步直接围绕 `v0.2.x Local Data MVP` 开发，不再扩展新产品功能。

优先顺序：

```text
1. 0.2.0 版本规划与本地数据边界冻结
2. 0.2.1 PowerSync Local Core 基础底座
3. 0.2.2 audit_logs 与本地写入公共工具
4. 0.2.3 memo 本地 CRUD 闭环
5. 0.2.4 task 本地 CRUD / complete 闭环
6. 0.2.5 expense 本地 create/search/summary 闭环
7. 0.2.6 Flutter 页面切换到 Local Core 模式
8. 0.2.7 本地持久化回归与重启验证
9. 0.2.8 v0.2 release gate 与文档收口
```

判断标准：

```text
只要 memo / task / expense 可以离线写入并重启不丢，v0.2.x 的核心就成立。
```
