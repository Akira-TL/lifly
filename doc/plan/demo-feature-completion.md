# Lifly 功能补全版本计划

目标版本：`v0.9.0`

## 1. 版本定位

`v0.9.0` 是 Lifly 在路演前的功能封板版本。目标不是继续横向扩展产品，而是把现有产品地基补成一个真实可运行、可安装、可跨端、可 AI 执行、可证明隐私边界的完整闭环。

本版本结束后，`v0.9.1` 路演版原则上不再新增底层能力，只做体验、视觉、稳定性和演示收口。

并行开发的 worktree / Agent 文件所有权、Wave 0/1/2 依赖和集成顺序，以 `doc/plan/v0.9.0-parallel-work-allocation.md` 为准；该文件只负责执行拆分，不改变本文件定义的产品范围。

### 1.1 2026-08-16 架构收口与 Demo Delivery Hardening 状态

核心架构合同已完成一轮收口，并由 `scripts/check-v0.9.0-release-gate.sh` 证明：encrypted write 与 local projection 同事务、SQLCipher at-rest encryption、Account Runtime State、持久 session/OPAQUE flow、结构化 AI Candidate ingestion、Device AI crypto conformance、relay 原子 claim 与 PowerSync publication scope 均已进入门禁。`CONTRACT_GATE=PASS` 不等价于跨设备实机 Golden 已完成。

当前剩余工作严格转为交付层，不再继续扩大核心架构：

- Web：同源 OPAQUE WASM + `sqlite3mc.wasm` release build；
- Android：OPAQUE Rust `cdylib` 通过 Dart FFI 内置到 APK，debug Demo 包可构建；正式 release 必须存在本地 keystore 并通过 `apksigner`，缺签名时门禁直接阻断；
- Linux Desktop：Flutter release bundle 内置 native OPAQUE；
- Desktop Compute Node：采用 **Desktop Client + Compute Node Companion** 同一交付包的模型，Companion 具有独立 Device Identity 和 compute capability，worker/Local Core 在构建时预编译；Demo 允许宿主 Node、uv、Ollama，并由 launcher 显式检查；
- Windows：已保留 native OPAQUE DLL/package seam，但必须在真实 Windows host 构建验收，WSL 不能替代；
- WSL 缺 `org.freedesktop.secrets` 只属于 Linux/WSL Secret Service 环境阻断，禁止加入明文文件密钥 fallback。

跨端构建/签名/companion 状态统一由 `scripts/check-v0.9.0-delivery-gate.sh` 汇总；该 gate 不自动执行 Golden live。

## 2. Demo 必须能够证明的核心故事

```text
手机号账号登录
  ↓
Android / Web / Desktop 属于同一 Account
  ↓
本地记录 Memo / Ledger / Task
  ↓
E2EE 同步，云端只保存 ciphertext
  ↓
手机可把 AI Job 路由到自己的 Desktop Compute Node
  ↓
Desktop Ollama / 用户自配 AI + MCP 执行
  ↓
Lifly 云端中继看不到 Job 明文
  ↓
用户也可明确授权 Lifly Cloud AI 临时处理必要数据
  ↓
AI 返回结构化动作
  ↓
客户端验证、提交、审计、撤销
```

## 3. 功能补全范围

### 3.1 Account / Auth / Device Registry

必须完成：

- 手机号作为第一版唯一 Account Identity；
- Demo 阶段手机号直接注册，不做短信验证码；
- 密码不以明文或固定可重放哈希上传；优先采用成熟 OPAQUE/aPAKE 实现；
- 基础 access/refresh session 与 revoke；
- Flutter Secure Secret Store；
- 所有云端业务入口从认证上下文推导 account/user，不再信任客户端提交任意 `user_id`；
- 清理生产路径 `local-dev`；
- Device Registry；
- 每设备 Device Identity / public key；
- Demo Security Profile：密码认证成功即可自动 trusted enrollment；
- 一个 Account 同一时间最多一台 Default Compute Node；
- Device capability 至少支持 `local_ai / local_mcp / background_executor`；
- 默认节点离线时不自动改送 Lifly Cloud AI。

明确后置：短信验证码、Recovery Key、二维码配对、旧设备批准、复杂风控、自助账号找回、OAuth、正式运营后台。

### 3.2 E2EE 数据平面

必须完成：

- Account Data Key；
- Demo Password Key Envelope；
- 成熟 AEAD 加密实现，禁止自创协议；
- `EncryptedSyncStore` 深模块；
- Memo / Ledger / Task / AI Capture 等正式业务 payload 云端只保存 ciphertext；
- 本地 decrypted projection / Local Core 继续承担搜索、统计、首页、分类、预算、预警；
- revision / tombstone / conflict 在密文模型下仍可工作；
- 现有 plaintext 开发数据迁移路径；
- release gate 能证明云端数据库不可 grep 到测试正文/金额/任务内容；
- 本地 SQLite at-rest encryption；
- 密钥、token、AI API Key 不落 SharedPreferences 或业务库明文字段。

### 3.3 附件 / Audit / Export E2EE

必须完成，因为否则不能真实宣称 E2EE：

- 附件客户端加密后上传 MinIO；
- per-asset key / wrapped key；
- `assets` / `memo_asset_refs` 正式同步；
- Audit `source_text / before_snapshot / after_snapshot` 加密；
- 删除/清理不残留明文历史；
- export 明确区分 plaintext export 与 encrypted backup；
- plaintext export 给出敏感数据提醒。

### 3.4 PowerSync / 云同步真实可用

必须完成：

- 更新当前自托管 PowerSync 配置到实际可运行版本；
- source DB replication / bucket / client auth 配置收口；
- PowerSync 不再默认长期处于“设计存在但关闭”的状态；
- Android / Desktop / Web 至少完成 Demo 所需跨端同步实测；
- 附件 metadata / refs 和业务 encrypted envelopes 均进入同步合同；
- 同步状态 UI 使用真实状态；
- 多端 ID / revision / tombstone 一致。

### 3.5 AI Provider

建立一个小而深的 `AiProvider` interface。

第一版实现：

```text
OllamaAiProvider
OpenAiCompatibleProvider
LiflyCloudAiProvider
```

要求：

- Lifly 自有云 AI 默认可使用服务端本地 Ollama；
- 用户可在自己的 Desktop Node 配置 Ollama 或 OpenAI-compatible Provider；
- API Key 只存 Secure Secret Store；
- Provider 不直接写数据库；
- AI 只产生结构化候选动作；
- 现有 deterministic parse / validator 继续作为 fallback 和安全验证层；
- malformed output / timeout / provider unavailable / invalid action 必须 fail closed 或 fallback。

### 3.6 Personal Compute Node / Local MCP

必须完成当前隐藏的实际断点：

- Desktop Local Core Bridge 从 placeholder/unavailable 变为真实接线；
- Local MCP 复用正式 tool schema / validation / audit / undo；
- Desktop 可作为 Personal Compute Node；
- Device Registry 上报 capability / health / last_seen；
- Mobile 可选择 Default Compute Node；
- E2EE AI Job relay 使用 target_device_id + ciphertext；
- Job 支持 idempotency / expiry / retry / offline queue；
- 云端 relay 不持有解密密钥；
- Desktop Node offline 不静默改投 Cloud AI。

### 3.7 Lifly Cloud AI 授权路径

必须完成最小可展示版本：

- Cloud AI Disclosure 明确显示发送目标、数据范围和原因；
- 用户主动确认后才发送；
- 只发送本次必要的最小上下文；
- Stateless Inference Gateway；
- request/response body 不进 DB、日志、analytics、trace payload；
- server-side Ollama 推理；
- 返回 candidate actions；
- 客户端本地 validate / commit / audit / undo；
- Cloud AI 永远拿不到 ADK。

第一版授权可以只做 `once`，不必在功能补全版实现复杂 session/scoped preference。

### 3.8 Android 真机闭环

必须完成：

- 正式 applicationId；
- app label / icon；
- release INTERNET permission；
- versionName / versionCode；
- release signing 基础；
- Android Secure Secret Store；
- encrypted local DB；
- 系统通知 adapter；
- reminder permission / scheduling；
- 真机登录、记录、离线、恢复联网、同步、提醒；
- 手机发送 AI Job 到 Desktop；
- 手机明确授权使用 Lifly Cloud AI。

### 3.9 当前产品消费层遗留

只补会影响 Demo 完整性的部分：

- Memo AI 分类/标签 UI 消费；
- Ledger 预算、分类占比、月环比/必要洞察 UI；
- Task reminder strategy / delivery status UI；
- Home 待确认动作/任务预警必要排序；
- AI 附件至少明确能力状态；若 PDF/OCR/STT 无法在本版本稳定完成，可在路演路径中不依赖它们，但 UI 不得伪造支持；
- 搜索 / 设置 / 诊断与数据状态的明显断链修复；
- 详情页删除/恢复/双击提交/重试等已知固定点问题收口。

### 3.10 工程与发布技术债

必须完成：

- 正式 DB migration runner，至少覆盖 v0.9.0 新增 schema；
- app / API / script 版本号统一；
- dev / blue / green / common 端口规则不回归；
- 所有 runtime 启停继续只走 `scripts/*.sh`；
- 新增 `scripts/check-v0.9.0-release-gate.sh`；
- release gate 组合 API / Flutter / MCP / E2EE / sync / Android 必要静态和自动测试。

## 4. 建议原子开发顺序

按依赖关系，不按页面顺序：

```text
A. Auth / Device Registry / Secure Store
B. Crypto spike + Password Key Envelope
C. EncryptedSyncStore + PowerSync 真实同步
D. Assets / Audit encryption
E. AI Provider + Ollama
F. Desktop Local Core Bridge + Local MCP
G. E2EE AI Job Relay
H. Lifly Cloud AI Disclosure / Stateless Inference
I. Android notification + 真机闭环
J. 产品消费层遗留 + 技术债
K. v0.9.0 release gate
```

每一组应拆成多个原子 commit，不把整个版本压成一个提交。

## 5. v0.9.0 完成定义

版本完成时必须真实通过以下人工 Demo：

```text
1. 手机号注册并登录。
2. 手机与电脑出现在同一 Device Registry。
3. 手机创建 Memo / Expense / Task，断网时仍可用。
4. 恢复联网后电脑看到同步数据。
5. 云数据库检查不到业务明文。
6. 手机要求 AI 处理一条混合生活输入。
7. 默认 Desktop Node 使用本地 Ollama + MCP 生成/执行结构化动作。
8. 手机能够查看结果并撤销/修改。
9. Desktop Node 离线时不会偷偷上传 Cloud AI。
10. 用户主动选择 Cloud AI 后明确看到授权范围，云端 Ollama 返回候选动作。
11. 任务提醒在 Android 系统真实弹出。
12. 附件、Audit 不形成明文旁路。
```

做到这里，Lifly 才进入“路演只需要打磨”的状态。
