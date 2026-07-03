# 59. Lifly 版本控制与后续开发计划

## 1. 当前版本判定

当前 Lifly 已完成 AI Write 版本族收口：

```text
v0.4.11
```

当前开发准备进入 v0.5 版本族：

```text
v0.5.0 Assets & Import/Export 全量开发
```

含义：

```text
当前稳定 tag：v0.4.11
当前开发分支：develop/v0.5.0（待创建）
当前开发版本族：v0.5.x
版本号规则：从 v0.2 开始不再使用 dev 后缀，开发轮次使用 0.5.0、0.5.1、0.5.2 这类标准三段式修订号
```

v0.5 的目标是让附件 metadata、内部文件上传体验、外部链接引用、CSV 导入预览/提交/回滚和基础导出形成完整闭环。

## 2. 版本号规则

Lifly 使用 SemVer 风格版本号：

```text
MAJOR.MINOR.PATCH
```

规则：

```text
MAJOR：破坏性架构变化，或正式公开发布后的不兼容变更
MINOR：新增一组完整产品能力，例如本地离线、云同步、Local MCP、导入导出
PATCH：同一能力版本族内的修订号，用于拆分可验证开发轮次、缺陷修复、测试补强和发布门禁
```

从 v0.2 开始，开发过程也使用标准三段式版本号，不再写 `dev` 后缀。

示例：

```text
v0.1.0
v0.2.0
v0.2.1
v0.2.2
v0.2.8
v0.3.0
v1.0.0
```

## 3. Git 分支与 Tag 规则

推荐分支模型：

```text
develop/master：开发主干，只合并已验证的版本分支
master：稳定主干，后续只保留正式稳定发布
版本开发分支：develop/vX.Y.Z，例如 develop/v0.4.0
临时功能分支：仅在确实需要并行实验时使用，合并前必须回到对应 develop/vX.Y.Z
```

版本分支生命周期：

```text
1. 每个修订号从 develop/master 单独开 develop/vX.Y.Z
2. 当前版本分支只做当前修订号内的内容
3. 当前版本完成后，先合并回 develop/master
4. 在 develop/master 的合并点打最终 tag，例如 v0.4.0
5. tag 完成后删除当前 develop/vX.Y.Z 分支
6. 进入下一个修订号前，再新开下一个 develop/vX.Y.Z 分支
```

当前 v0.5.0 计划开发分支：

```text
develop/v0.5.0
```

推荐 tag 规则：

```text
v0.1.0
v0.2.0
v0.2.1
v0.2.2
v0.2.8
v0.3.0
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

### v0.2.x：Local Data MVP

主题：本地优先的手动记录闭环。

修订号计划见：

```text
docs/development-plans/v0.2.0-local-data-mvp.md
```

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

### v0.4.x：AI Write 全量开发

状态：已完成，最终 tag 为 `v0.4.11`。

主题：AI 写入成为 Lifly 的完整一等入口。

范围：

```text
Cloud MCP / Local MCP 统一 tool schema
Cloud MCP 直接写入 memo / task / expense / asset ref
Local MCP 通过真实 Dart Local Core 写入本地数据
capture_parse / capture_commit / capture_undo 全量闭环
Flutter AI Capture 输入、候选确认和撤销入口
AI 写入和撤销全部进入 audit logs
AI undo 进入 ai_trashed，不物理删除
Cloud / Local MCP parity tests
AI Write smoke 与 release gate
```

验收：

```text
Cloud MCP 可完整写入 memo / expense / task / asset ref
Local MCP 离线可完整写入 memo / expense / task
capture_commit 支持全部提交和部分提交
capture_undo 可追踪并移动到 AI trash
Flutter 可触发 AI 写入、确认和撤销
Cloud 与 Local MCP 复用同一套 protocol schema
所有 AI 写入和撤销都有 audit logs
```

### v0.5.0：Assets & Import/Export 全量开发

状态：下一阶段入口。

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

## 7. 当前推荐下一批修订号

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
