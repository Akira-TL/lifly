# Desktop Personal Compute Node / Local MCP 设计

> v0.9.0 起，Desktop 不只是“本地 MCP 兜底端”，还可以作为 Account 的 Personal Compute Node，承接其他 Trusted Device 发来的端到端加密 AI Job。

## 1. 定位

Desktop 运行时承担两类相互复用但不同入口的能力：

### 1.1 Local MCP

用于本机 Hermes、OpenClaw、本地 Agent 等通过 stdio 调用 Lifly 工具。

### 1.2 Personal Compute Node

用于 Android / Web / 其他 Device 把 AI planning Job 加密路由到用户自己的 Desktop，并由 Desktop 上的 Ollama 或 OpenAI-compatible Provider 执行。

两条入口最终都必须复用 Desktop Local Core，不产生第二套业务逻辑。

Android 不运行 MCP Server；Android 可以作为 encrypted AI Job Requester。

### 1.3 v0.9.0 Desktop 交付边界

v0.9.0 不把全部 Compute Node 逻辑重写进 Flutter 进程，而采用同一 Desktop 交付包内的两个本地运行时：

```text
Desktop Client
  └─ Flutter UI / SQLCipher / PowerSync / 本机业务操作

Compute Node Companion
  └─ 独立稳定 Device Identity
  └─ local_ai / local_mcp / background_executor
  └─ encrypted relay worker
  └─ Local Core Bridge
  └─ Ollama / 用户自配 Provider
```

二者可以安装在同一台电脑，但 Device Registry 语义不得混淆：只有真正管理 worker 生命周期的 Companion 才声明 compute capabilities，也由 Companion 承担 Default Compute Node 角色。Desktop Client 不得为了 UI 显示方便虚假上报 capability。

Demo bundle 必须预编译 Local MCP worker 与 Local Core bridge，提供单一 Companion launcher；运行时不得再要求现场执行 `pnpm build`。v0.9.0 Linux Demo 允许宿主已安装 Node、uv 与 Ollama，这些依赖由 launcher `--check-env` 明确验证。Windows 必须在真实 Windows host 重新构建并验收，不以 WSL 构建结果替代。

## 2. 非目标

Desktop Local MCP / Compute Node 不负责：

- 绕过 Local Core 直接写 SQLite；
- 绕过 E2EE write seam；
- 在 Cloud Relay 上发送 prompt 明文；
- 让 Provider 直接提交 Memo / Ledger / Task；
- Default Compute Node 离线后自动改用 Lifly Cloud AI；
- 把 Device Private Key 或 ADK 上传到 Device Registry。

## 3. Local MCP 传输

Local MCP 默认采用 stdio：

```text
Hermes / Local Agent
       ↓ stdio
Local MCP Server
       ↓
Desktop Local Core Bridge
```

原因：

- 不开放默认网络端口；
- 适合本地 Agent 进程模型；
- 与 Hermes / OpenClaw 本地工具调用方式兼容；
- 安全 seam 清晰。

如果未来增加 localhost HTTP transport，必须显式开启、绑定 loopback，并单独定义认证，不得替代默认 stdio 模式。

## 4. Desktop Local Core Runtime

Local MCP 和 Compute Node 在使用业务数据前都需要初始化 Desktop Local Core runtime：

```text
Account ID
ADK + key_version
Local SQLCipher database key
        ↓
Desktop Local Core Host
        ↓
EncryptedSyncStore
        ↓
Local mutation committer
        ↓
Audit payload protector
        ↓
PowerSyncLocalCoreBridge
```

Desktop host 在 runtime init 之前不得接受正式业务调用。

旧 plaintext 本地数据可以在 unlock/bootstrap 时执行一次兼容迁移，但正常新写入必须直接进入事务 E2EE seam。

## 5. Local MCP 工具 Schema

Local MCP 与其他 MCP integration 共用正式 tool schema / validation contract。

禁止 Local MCP 私自定义不兼容业务动作。新增工具必须先进入 shared protocol，并保持：

- 相同输入验证；
- 相同实体状态机；
- 相同 audit；
- 相同 undo；
- 相同 revision；
- 相同 Local Core commit 语义。

## 6. Local MCP 写入路径

```text
Local Agent
   ↓ tool call
Local MCP handler
   ↓
Desktop Local Core Bridge
   ↓
Local Core business rule
   ↓
SQLCipher local projection
   ↓ same transaction
EncryptedSyncStore
   ↓
encrypted_entities
```

Local MCP 不允许直接 SQL 写主业务表。

## 7. Personal Compute Node

### 7.1 Device capability

Desktop 可以向 Device Registry 声明：

```text
local_ai
local_mcp
background_executor
```

只有属于同一 Account、处于 trusted 且未 revoked 的 Device 才能参与 encrypted AI routing。

### 7.2 Default Compute Node

一个 Account 同一时间最多一个 Default Compute Node。

用户也可以在支持的 UI 中临时选择其他 Trusted Compute Node。

Default Compute Node 的语义是“默认执行目标”，不是“云 AI fallback policy”。

## 8. Encrypted AI Relay

Requester Device 与 Desktop Compute Node 之间使用 Device-to-Device crypto：

```text
Requester Device
    ↓
X25519 shared secret
    ↓
HKDF-SHA256 context key
    ↓
AES-256-GCM
    ↓
Encrypted AI Job
    ↓
Cloud Relay
    ↓
Desktop Compute Node
```

Cloud Relay 只允许看到：

```text
account_id
source_device_id
target_device_id
message_type
correlation_id
idempotency_key
expires_at
delivery status
ciphertext / nonce
```

不得获得 prompt / context / result 明文。

## 9. 跨语言 Crypto Contract

Flutter Requester 与 TypeScript Compute Node 必须严格一致：

```text
X25519
HKDF-SHA256
AES-GCM-256
12-byte nonce
128-bit tag
```

还必须固定：

- key domain；
- AAD domain；
- context 字段顺序；
- protocol version；
- encryption version；
- expiry 的 UTC millisecond canonicalization；
- Base64 / Base64URL encoding。

任何一端改变 wire contract 都必须有跨语言 fixture / integration test，不允许“各自单测通过”代替互操作验收。

## 10. Relay Worker 生命周期

Desktop Compute Node worker 采用拉取式生命周期：

```text
poll next encrypted job
      ↓
decrypt + validate
      ↓
execute planner/provider
      ↓
produce candidate actions
      ↓
encrypt result
      ↓
submit result
```

Job 至少具备：

- idempotency；
- expiry；
- attempt count；
- in-flight deduplication；
- terminal failed / expired 状态；
- result correlation。

Worker 对可重试错误不能提前把 Job 标为 terminal failed；不可重试错误才进入 fail path。

## 11. Provider 执行

Compute Node 可以使用：

```text
Ollama
OpenAI-compatible Provider
Deterministic Local Core fallback
```

Provider 只生成结构化 candidate actions。

Provider 失败、timeout、malformed output、invalid action 时必须 fail closed 或进入明确 fallback，不允许把不受验证的输出直接写数据库。

用户 Provider API Key 只能存 Secure Secret Store，不得进入业务库或 Relay payload。

## 12. Candidate Action 的最终提交

Compute Node 返回的是候选动作，不是已经完成的业务写入。

Requester Device 收到并解密结果后：

```text
candidate action
     ↓
本地 validator / UI
     ↓
LocalCoreExternalAiActionCommitter
     ↓
Capture revise / commit
     ↓
Local Core
     ↓
Audit + Undo + E2EE sync
```

这样 Personal Compute Node、Lifly Cloud AI、本地规则最终共享同一业务 commit seam。

## 13. Offline 行为

### Desktop 自身离线

Local MCP 与 Desktop 手工业务仍可使用本地 SQLCipher / Local Core；PowerSync 恢复网络后继续同步。

### Requester 找不到 Desktop

Requester 必须明确显示 Compute Node unavailable。

```text
Compute Node offline
       ≠
automatic Cloud AI disclosure
```

只有用户显式选择并确认 Lifly Cloud AI Disclosure 后，才允许发送本次必要明文。

## 14. 安全边界

必须保持：

- Local MCP 默认只监听 stdio；
- Device private key 只在本机 Secure Secret Store；
- ADK 只用于账户业务 E2EE，不作为云端 relay key；
- AI Job 使用 Device-to-Device key agreement；
- Relay 服务端只做 authenticated routing；
- revoked Device 不得领取或提交新 Job；
- Request / Result 必须校验 Account、source、target、correlation、idempotency 和 expiry；
- Provider 日志不能输出用户 prompt、ADK、Device private key 或 API Key。

## 15. 当前 hardening 重点

v0.9.0 仍需通过真实设备验证：

- Desktop 重启后 Device Identity 稳定；
- Default Compute Node 状态与 Device Registry 一致；
- Requester / Desktop crypto 真正跨语言互操作；
- retry / duplicate delivery 不产生重复业务动作；
- Ollama 首次加载、timeout 和离线错误可理解；
- Desktop Local Core 与 Flutter Desktop 不产生数据库并发破坏；
- worker 重启后 Job lifecycle 不漂移；
- Compute Node 离线永不隐式切换 Cloud AI。
