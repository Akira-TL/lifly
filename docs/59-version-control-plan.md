# 59. Lifly 版本控制与后续开发计划

## 1. 当前版本判定

当前 Lifly 统一定为：

```text
v0.1.0-dev
```

含义：

```text
代码包版本：0.1.0
Flutter 应用版本：0.1.0+1
API health version：0.1.0
发布状态：development，尚未切正式 release tag
```

项目已经超过空仓库和纯文档阶段，进入 v0.1.0 的开发后半段；但还没有达到可正式标记 `v0.1.0` release 的状态。正式 `v0.1.0` 应在本地基础闭环、Cloud API/MCP smoke、Flutter 基础页面、CI 和命名一致性全部稳定后再打 tag。

## 2. 版本号规则

Lifly 使用 SemVer 风格版本号：

```text
MAJOR.MINOR.PATCH[-PRERELEASE]
```

规则：

```text
MAJOR：破坏性架构变化，或正式公开发布后的不兼容变更
MINOR：新增一组完整产品能力，例如本地离线、云同步、Local MCP、导入导出
PATCH：缺陷修复、文案调整、测试补强、小范围兼容改动
PRERELEASE：alpha / beta / rc / dev，用于正式 release 前的阶段标记
```

示例：

```text
v0.1.0-dev
v0.1.0-alpha.1
v0.1.0-beta.1
v0.1.0-rc.1
v0.1.0
v0.2.0
v1.0.0
```

## 3. Git 分支与 Tag 规则

推荐分支模型：

```text
master：稳定主干，只合并已验证 PR
fix/vX.Y-release-gate：版本收口分支，例如 fix/v0.1-release-gate
feat/<issue-slug>：功能开发分支
fix/<issue-slug>：缺陷修复分支
release/vX.Y.Z：发布候选分支，只做修复、不加新功能
```

版本分支生命周期：

```text
1. 每个版本单独开一个版本收口分支
2. 当前版本分支只做当前版本 release gate 内的内容
3. 当前版本完成后，先合并回 master
4. 在 master 的合并点打最终 tag，例如 v0.1.0
5. tag 完成后删除该版本收口分支
6. 进入下一个版本前，再新开下一个版本分支
```

当前 v0.1.0 收口分支：

```text
fix/v0.1-release-gate
```

推荐 tag 规则：

```text
v0.1.0-alpha.1
v0.1.0-beta.1
v0.1.0-rc.1
v0.1.0
v0.2.0
```

每个 release tag 必须满足：

```text
pnpm test
pnpm typecheck
cd apps/client_flutter && flutter analyze
cd apps/client_flutter && flutter test
后端 API/MCP integration 或 smoke 测试通过
docs 中版本说明已更新
```

## 4. 当前 v0.1.0 Release Gate

`v0.1.0` 的目标不是完整商业产品，而是 Lifly 的第一个可验证技术基线。

必须完成：

```text
项目命名统一为 Lifly / lifly
pnpm workspace 依赖与 lockfile 稳定
Protocol / Local Core / Local MCP 测试通过
Flutter analyze/test 通过
FastAPI health 与版本号统一
Cloud API 基础模块可启动
MCP v0.1 tool schema 冻结
Flutter 基础页面可展示 memo / ledger / task / asset / settings
Local MCP / Local Core fake 链路存在并可测试
```

可以不完成：

```text
真实本地持久化
PowerSync uploadData
跨端同步
Local MCP 调用 Flutter/Dart 真实 Local Core
生产级登录/鉴权
完整附件上传体验
完整导入导出体验
```

## 5. 后续版本拆分

### v0.1.0：Foundation Baseline

主题：统一项目基线，确保当前代码库可持续开发。

范围：

```text
命名统一
workspace lockfile
CI 基础测试
Cloud API 基础健康检查
MCP v0.1 schema
Flutter 基础页面
Local Core fake
Local MCP stdio skeleton
版本规划文档
```

验收：

```text
pnpm test 通过
pnpm typecheck 通过
flutter analyze 通过
flutter test 通过
仓库无历史项目名残留
打 tag：v0.1.0
```

### v0.2.0：Local Data MVP

主题：本地优先的手动记录闭环。

范围：

```text
Flutter PowerSync schema 实际启用
Dart PowerSyncLocalCoreBridge
memo 本地 create/search/update/delete
task 本地 create/list/complete/update/delete
ledger expense 本地 create/search/summary
本地 audit_logs 写入
revision / deleted_at / status 状态维护
基础本地搜索
```

验收：

```text
无网络可创建 memo / expense / task
应用重启后数据不丢
所有本地写操作有 audit log
Flutter 页面可切换或默认走 Local Core
```

### v0.3.0：Cloud Sync MVP

主题：PowerSync 云同步闭环。

范围：

```text
PowerSync uploadData 实现
后端同步写入 endpoint
PostgreSQL schema 与 Flutter schema 对齐
登录/token 基础接入
Windows 与 Android 跨端同步
删除状态同步
冲突处理最小策略
同步状态 UI
```

验收：

```text
Windows 创建，Android 可见
Android 离线创建，联网后 Windows 可见
删除/恢复状态跨端一致
同步失败可诊断
```

### v0.4.0：AI Write MVP

主题：Cloud MCP 与 Local MCP 都能写入 Lifly 数据。

范围：

```text
Cloud MCP v0.1 contract 稳定
Local MCP stdio 接真实 Dart Local Core
Local MCP bridge transport
capture_parse / capture_commit / capture_undo 本地闭环
memo_create / expense_create / task_create 本地闭环
AI 写入 audit log
AI undo 进入 ai_trashed，不物理删除
Hermes / 本地 MCP 配置文档
```

验收：

```text
Cloud MCP 可创建 memo / expense / task
Local MCP 离线可创建 memo / expense / task
capture_commit 返回 undo_token
capture_undo 可追踪并移动到 AI trash
Cloud 与 Local MCP 复用同一套 protocol schema
```

### v0.5.0：Assets & Import MVP

主题：附件与导入导出形成可用闭环。

范围：

```text
asset_create_upload_url
asset_register_external_url
MinIO / 对象存储适配
memo asset 引用
通用 CSV 导入预览
支付宝 / 微信 CSV parser
import_batch / import_rows / preview / commit
导入批次回滚
Markdown / CSV / JSON 导出
```

验收：

```text
图片或文件可注册为 asset metadata
外链可保存并在 UI 展示
CSV 不直接写正式账单表
导入前可预览
导入后可按 batch 回滚
核心数据可导出
```

### v0.6.0：Private Alpha

主题：个人可长期试用的 Alpha 版。

范围：

```text
首页体验整理
错误处理与空状态
搜索增强
基础统计
设置页诊断完善
数据备份/恢复策略
日志与崩溃诊断
基础安全加固
```

验收：

```text
可作为个人主力测试工具使用
常见错误有可读提示
数据可备份和恢复
核心路径连续使用一周不丢数据
```

### v0.7.0：Private Beta

主题：接近真实发布前的稳定性版本。

范围：

```text
Android 端体验补齐
Windows 安装包
自动更新策略初版
性能优化
数据库 migration 体系
更完整的测试覆盖
隐私政策 / 用户协议草案
```

验收：

```text
Windows + Android 双端可安装使用
升级不破坏已有数据
主要功能有回归测试
可以邀请小范围用户测试
```

### v1.0.0：Personal Production

主题：个人生产可用版本。

范围：

```text
本地记录稳定
云同步稳定
Cloud MCP / Local MCP 稳定
附件与导入导出稳定
审计/回收站稳定
基本隐私与安全策略完成
发布包和文档完整
```

验收：

```text
普通用户可安装、记录、查询、同步、备份、恢复
AI 写入路径安全可追踪
数据删除可恢复/可审计
主要平台构建和测试通过
```

## 6. Issue 编号建议

继续使用 `LC-xxxx`，按版本段切分：

```text
LC-01xx：v0.1 foundation
LC-02xx：v0.2 local data
LC-03xx：v0.3 cloud sync
LC-04xx：v0.4 AI/MCP write
LC-05xx：v0.5 assets/import/export
LC-06xx：v0.6 alpha polish
LC-07xx：v0.7 beta/release hardening
```

每个 Issue 必须包含：

```text
目标
范围
禁止事项
验收标准
相关文档
测试命令
```

## 7. 当前推荐下一批 Issue

```text
LC-0101 Finish v0.1 baseline release checks
LC-0102 Remove legacy Lifly naming residues and lock workspace dependencies
LC-0201 Implement Dart PowerSyncLocalCoreBridge memo/task minimal write path
LC-0202 Add local audit log writer for Dart Local Core
LC-0203 Switch Flutter memo/task pages to Local Core in local mode
LC-0301 Implement PowerSync uploadData to Cloud API
LC-0401 Connect Local MCP transport to Dart Local Core Bridge
```
