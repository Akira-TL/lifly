# E2EE、私有 AI 与个人计算节点开发计划（草案）

## 1. 背景

Lifly 已完成备忘、记账、任务、AI Capture、Local Core、PowerSync 数据层、审计、撤销和多端 UI 的主要产品地基。下一阶段不再横向扩展业务模块，而是把隐私、安全、AI 执行和移动端真实使用所需的技术债收口。

本计划确立新的长期原则：

```text
用户拥有数据
用户拥有密钥
云端默认只保存密文
用户自有 AI 路径下 Lifly 云端无法读取业务明文
Lifly Cloud AI 只能处理用户明确授权披露的最小数据，并且不持久化 prompt / context / response
AI 只生成结构化候选动作，最终业务写入仍经过客户端 Local Core / Validator / Audit / Undo
```

本计划为临时执行计划。各阶段完成后，应把最终合同回写到 requirements / architecture / api / design / legal / guide，并删除本文件。

> **实施状态（2026-08-16）**：v0.9.0 的核心 E2EE/私有 AI 架构 seam 已实现并进入 release gate：正常 Local Core 写入不再依赖全表 plaintext migrator；SQLCipher at-rest encryption 与旧明文库迁移有 packaged smoke；Account/E2EE/Sync 可用性已显式建模；External AI Candidate 直接进入统一 Local Core ingestion；Device AI Job 有 Dart/TypeScript 共用 crypto vectors。当前阶段已转入 Demo Delivery Hardening，重点是 native OPAQUE packaging、Desktop Companion、签名与真实设备验收，不再重新设计 ADK/同步模型。

## 2. 安全边界

### 2.1 不把“账号认证”当成“数据解密”

账号认证和数据加密必须完全解耦：

```text
账号密码 / OAuth / session
        ↓
只证明“你是谁”
        ↓
服务器签发同步和账户权限

设备密钥 / Account Data Key
        ↓
只负责“你能否解密数据”
        ↓
服务器永远不持有可直接解密用户业务数据的主密钥
```

服务端数据库泄露、PowerSync 节点泄露、对象存储泄露时，不应直接暴露备忘正文、账单金额/商户/备注、任务正文/时间、AI 会话、审计快照或附件明文。

### 2.2 E2EE 的准确承诺

Lifly 的端到端加密覆盖：

- 客户端之间通过云同步传输和保存的业务数据；
- 附件内容；
- AI Capture 会话和结果；
- 审计正文和 before/after snapshots；
- 跨设备 AI Job（用户自有电脑执行时）。

Lifly Cloud AI 是用户主动发起的“选择性披露”通道，不属于服务器透明解密：

- 用户设备本地解密；
- UI 明确展示将发送的数据范围和目标 Provider；
- 客户端只发送本次推理所需最小上下文；
- 云推理服务仅在内存中处理；
- 禁止将 prompt / context / response 写入数据库、对象存储、常规日志、trace payload 或分析系统；
- 返回结构化候选动作后，由客户端本地 Validator + Local Core 决定是否提交；
- 云端永远不获得 Account Data Key。

## 3. 密钥体系

### 3.1 设备身份

每个受信设备生成独立 Device Key Pair：

```text
Device Private Key
  Android -> Android Keystore
  iOS/macOS -> Keychain / Secure Enclave 可用时优先
  Windows -> OS credential / key protection adapter
  Web -> 单独设计浏览器设备密钥策略，不复用明文 SharedPreferences

Device Public Key
  可上传云端，用于设备注册和密钥 envelope
```

私钥不可通过普通同步上传。

### 3.2 Account Data Key

首次启用 E2EE 时，由客户端生成随机 Account Data Key（ADK）。ADK 永远不以明文上传云端。

为了加速 Demo，第一阶段不做“已有设备批准 + 每设备 ADK envelope”的完整生产级 enrollment，而采用 **Password Key Envelope**：

```text
用户密码
  ↓ OPAQUE / aPAKE
client-only export key
  ↓ application-specific KDF
ADK wrapping key
  ↓
wrap(ADK)
  ↓
云端只保存 Password Key Envelope
```

要求：

- 密码本身不上传服务端；
- 服务端拿不到 client-only export key；
- 服务端拿不到 ADK wrapping key；
- 新设备密码认证成功后，在客户端重新得到相同的 client-only key，并解开 Password Key Envelope；
- Device Key Pair 仍然保留，用于设备身份、AI Job 端到端加密和未来升级到每设备独立 key envelope；
- 不允许把密码本身直接当作业务数据加密密钥。

该方案是 Demo Security Profile 的简化 enrollment；未来生产安全配置可迁移到设备批准 + per-device envelope，而不改变 ADK 或已加密业务数据的基本模型。

### 3.3 Recovery / Password Loss（Demo）

Demo 阶段不实现独立 Recovery Key，不实现短信找回，也不实现设备间恢复批准。

忘记密码时由管理员处理 Account 凭据重置，但必须明确区分：

```text
管理员恢复 Account 登录能力
            ≠
管理员恢复 E2EE 数据
```

如果至少还有一台设备已经持有 ADK，可以在账号凭据重置后由该设备重新生成新的 Password Key Envelope。若用户同时忘记密码且所有持有 ADK 的设备都不可用，则旧 E2EE 数据不可恢复。

Demo 阶段接受这个限制，禁止为了“管理员可找回”而保存服务端万能解密密钥。Recovery Key、可信设备批准和完整安全恢复流程留到 Demo 后 Hardening。

### 3.4 Key Version / Rotation

所有 encrypted envelope 必须携带 `key_version`。

需要支持：

- 新设备加入；
- 设备撤销；
- ADK rotation；
- 后台渐进式 re-encryption；
- 旧 key envelope 回收；
- 恢复过程中不发生 silent data loss。

设备撤销只能阻止未来授权和同步，不能远程抹去已被该设备读取的历史明文；产品和安全文档必须明确这一物理边界。

## 4. E2EE 同步数据平面

### 4.1 不继续同步业务明文字段

当前 PowerSync domain tables 直接包含 `title / content_markdown / amount / merchant / due_at / source_text / snapshots ...`。E2EE 后不应继续把这些字段以明文写入云端 source database。

建议建立深模块：

```text
EncryptedSyncStore
```

对外 interface 只暴露：

```text
putEncryptedEntity(entity)
applyRemoteEnvelope(envelope)
watchSyncState()
rotateKey(...)
```

具体加密、nonce、AAD、序列化、版本迁移、PowerSync CRUD mapping 全部隐藏在模块内部。

### 4.2 云端同步 envelope

建议统一为最小同步 envelope，而不是继续让服务端理解每个业务实体的全部字段：

```text
encrypted_entities
  id
  user_id                 # 路由/授权需要，非业务正文
  entity_type             # memo/task/expense/...
  revision                # 冲突处理
  lifecycle_status        # active/tombstone 等最小同步状态
  updated_at              # 同步排序，可接受的元数据泄漏
  key_version
  encryption_version
  nonce
  ciphertext
```

真正业务 payload 全部进入 `ciphertext`：

```text
memo title/content/tags/mood
ledger amount/currency/merchant/note/category/time
task title/description/due/remind/priority
capture text/actions/context/results
classification
reminder content
审计 before/after/source_text
附件 metadata 中的敏感字段
```

是否需要把更多 metadata 留在明文中，必须逐字段通过 threat model 决定，默认答案应是“不留”。

### 4.3 Local Projection

Local Core 不应该每次查询都临时解密所有 ciphertext。

建议采用：

```text
PowerSync synced encrypted_entities
             ↓ decrypt/materialize
Local-only decrypted projection tables
             ↓
         Local Core
             ↓
 UI / search / overview / classification / reminder
```

当前 memos / tasks / ledger_transactions 等本地查询逻辑尽量保留，迁为 local-only projection；新增 E2EE Sync Adapter 负责：

- 本地 domain write 后序列化 + AEAD 加密 + 写 encrypted envelope；
- remote encrypted envelope 到达后验证 + 解密 + materialize；
- revision / tombstone / conflict；
- schema version migration；
- key rotation。

这样可以最大化复用现有 Local Core，并把加密复杂度集中在一个 seam。

### 4.4 本地数据库静态加密

E2EE 不替代设备数据库静态加密。

PowerSync SQLite 本地文件还需要单独启用数据库 encryption，数据库 key 从平台 Secure Secret Store 获取，不硬编码、不写 SharedPreferences。

因此：

```text
云同步：业务 payload E2EE
设备落盘：整个 SQLite 再做 at-rest encryption
```

是两层不同保护。

## 5. 附件 E2EE

对象存储只保存 ciphertext。

建议：

```text
asset plaintext
    ↓
随机 Asset Data Key
    ↓ chunked AEAD encryption
ciphertext chunks -> MinIO/Object Storage

Asset Data Key
    ↓ wrap with ADK
wrapped_asset_key -> encrypted asset metadata
```

需要解决：

- 大文件分块；
- 断点上传；
- hash/integrity；
- 下载后验证；
- MIME / filename 是否属于敏感 metadata；
- 本地缓存 purge；
- attachment key rotation；
- memo_asset_refs 与 asset metadata E2EE sync。

服务端生成的 upload URL 只能指向 ciphertext object，不能拿到 Asset Data Key。

## 6. AI 执行模型

AI 不直接拥有数据库写权限。

统一 pipeline：

```text
User Input
   ↓
AI Planner
   ↓
Structured Candidate Actions
   ↓
Deterministic Validator
   ↓
Local Core
   ↓
Audit / Undo
   ↓
E2EE Sync
```

保留现有 rule parser / time reasoning / risk validation 作为 fallback 和 Validator，不删除。

## 7. AI Provider 模块

建立：

```text
AiProvider
```

最小 interface：

```text
capabilities()
plan(request) -> structured candidate actions
health()
```

第一批 adapters：

1. `OllamaAiProvider`
2. `OpenAiCompatibleProvider`
3. `LiflyCloudAiProvider`

Provider 配置包含：

- endpoint；
- model；
- capability；
- secret reference（只引用 Secure Secret Store，不直接保存 API Key）；
- privacy boundary；
- whether data leaves device；
- health state。

UI 必须明确显示当前 AI 的真实执行位置。

## 8. 用户自有 AI：Lifly Personal Compute Node

用户自己的电脑端不是普通“AI Provider URL”，而是一个有设备身份和执行能力的可信节点：

```text
Lifly Personal Compute Node
  Device Key
  Local Core Bridge
  Local MCP
  AiProvider
    ├─ Ollama
    └─ OpenAI-compatible user endpoint
```

### 8.1 手机请求电脑执行

手机不需要运行 MCP。

推荐数据流：

```text
Mobile
  本地构造 AI Job
  ↓ 用目标 Desktop Device Public Key 加密
Encrypted AI Job
  ↓
Lifly Relay / PowerSync
  只见 ciphertext
  ↓
Desktop Node
  私钥解密
  ↓
Ollama / user AI
  ↓
Local MCP / Local Core 执行或产生候选动作
  ↓
Encrypted Job Result
  ↓
Mobile / other clients
```

云端中继只负责：

- target_device_id；
- job id；
- expiry；
- ciphertext；
- delivery status。

不保存可解密业务密钥。

### 8.2 Node 在线语义

需要真实状态，不伪造：

- online / offline / last_seen；
- provider health；
- capability list；
- supported tools；
- job expiry；
- retry / idempotency。

如果 Desktop Node 不在线：

- 用户可以等待 encrypted job；
- 改用 Lifly Cloud AI；
- 或使用本机确定性 fallback；
- 不能偷偷把明文改送云端。

## 9. Lifly Cloud AI：显式选择性披露

### 9.1 Consent Scope

每次云 AI 请求必须能说明：

```text
发送到哪里
使用什么模型/Provider
发送哪些类型的数据
具体数据范围
为什么需要
是否包含附件
是否包含历史上下文
```

支持的授权层级建议：

- once：仅本次；
- session：当前 AI 会话；
- scoped preference：仅指定数据类型/Provider，可随时撤销。

默认不建议使用永久“全部数据均允许上传”的单一开关。

### 9.2 Stateless Inference Gateway

Lifly Cloud AI 服务必须独立于主业务数据库：

```text
Client plaintext disclosure over TLS
      ↓
Stateless Inference Gateway
      ↓
Model runtime
      ↓
Structured response
      ↓
Client
```

硬约束：

- request/response body 不入数据库；
- request/response body 不进入 access log；
- 不进入 error monitoring payload；
- 不进入 analytics；
- 不进入 distributed tracing payload；
- 关闭模型服务的 prompt persistence；
- crash dump 不包含 request body；
- 超时/取消后立即释放；
- 只允许记录脱敏 operational metadata（request id、provider、model、latency、token count、status）。

### 9.3 Cloud AI 不直接写用户数据

云端只返回 candidate actions：

```text
memo_create
task_create
expense_create
...
```

客户端本地完成：

- schema validate；
- risk confirm；
- Local Core write；
- local encrypted audit；
- undo；
- E2EE sync。

这样云 AI 不需要 ADK，也没有“服务器代用户解密数据库”的后门。

## 10. Audit / Logging / Delete

### 10.1 Audit

Audit 也是用户敏感数据。

本地 audit payload 必须加密；同步后云端只保存 ciphertext。

需要重新定义：

- retention；
- purge；
- undo expiry；
- tombstone；
- legal/operational metadata 与用户内容 audit 的分离。

### 10.2 Cloud operational log

仅允许：

```text
request_id
user pseudonymous id（必要时）
provider/model
latency
token counts
status/error code
consent policy version
```

禁止：

```text
prompt
AI response
memo/task/ledger content
附件正文
密钥
完整 API key
decrypted audit snapshot
```

### 10.3 用户删除

删除需要覆盖：

- encrypted entity；
- tombstone retention；
- encrypted attachment object；
- wrapped attachment key；
- local cache；
- AI job ciphertext；
- Cloud AI 临时内存不存在持久化副本；
- operational metadata 按明确 retention policy 清理。

## 11. 账号、认证与 Device Registry

账号系统负责身份、设备目录、云服务权限和路由；它不负责解密用户业务数据。当前开发期 `local-dev` 必须退出生产路径。

### 11.1 Account 与 Encryption Identity 分离

必须保持：

```text
Account Identity
  手机号 / 登录认证 / session / 套餐 / Device Registry
                 ≠
Encryption Identity
  Device Key / Account Data Key / Recovery Key
```

服务器可以知道账号、手机号、设备列表、设备状态和云服务权限，但不能由这些信息推导 ADK 或业务明文。

### 11.2 手机号账号（Demo）

第一阶段只要求手机号注册/登录，不同时引入短信验证码、邮箱、OAuth 和社交账号。手机号统一规范化后作为唯一 Account Identity，并由数据库唯一约束防止重复注册。

Demo 阶段**不证明手机号真实归属**：用户输入一个未注册手机号即可创建账号。这是为了绕开短信资质和供应商接入，必须明确标记为 Demo-only，正式公开服务前再补手机号验证。

账号侧允许云端保存的用户信息限定为账户运营所需最小集合，例如：

- account_id；
- phone identity；
- display_name（可选）；
- account_status；
- plan / entitlement；
- created_at / security timestamps；
- Device Registry；
- 不含 E2EE 业务正文。

手机号属于 PII，需要独立访问控制、日志脱敏和静态保护；业务日志不得打印完整手机号。

### 11.3 密码不得以明文或可重放等价物上传

不能使用：

```text
HTTPS + plaintext password body
client SHA256(password) -> server
client fixed hash(password) -> server
```

固定客户端哈希一旦泄露，本身会成为可重放的等价密码。

目标认证协议采用成熟 PAKE/aPAKE；当前首选评估 OPAQUE（RFC 9807）：

- 注册期间服务器不获得用户密码；
- 登录期间服务器不获得用户密码；
- 服务端保存 OPAQUE credential record，而不是 `hashed_password`；
- 仍强制 TLS；
- 密码规则和泄露密码检查优先在客户端执行；
- 实施前必须验证 Flutter 与服务端可用库、互操作测试向量和安全维护状态，禁止自写密码协议。

Demo 阶段没有短信持有证明；手机号只作为登录标识。密码认证既用于 Account 登录，也可通过仅客户端可获得的认证导出密钥间接解开 Password Key Envelope，但密码本身不能直接充当 ADK。

### 11.4 Device Registry

每个 Account 拥有受服务端管理的 Device Registry。设备目录是路由和授权目录，不是解密目录。

建议最小设备记录：

```text
device_id
account_id
display_name
platform                 # android/windows/web/...
public_key
trust_state              # pending/trusted/revoked
capabilities             # local_ai/local_mcp/background_executor/...
is_default_compute_node
last_seen_at
created_at
revoked_at
key_version / protocol_version
```

服务端允许知道这些路由元数据，但不保存 Device Private Key、ADK 或明文 AI Job。

### 11.5 Device Enrollment（Demo）

Demo 阶段不做旧设备批准、二维码配对、Recovery Key 或强设备校验。

新设备流程简化为：

1. 手机号 + 密码完成 Account 认证；
2. 客户端自动创建 Device Identity / Device Key Pair，并注册到 Device Registry；
3. 客户端取得 Password Key Envelope；
4. 使用仅客户端可获得的密码认证导出密钥解开 ADK；
5. enrollment 自动完成，设备直接成为 trusted。

因此 Demo Security Profile 下，“知道账号密码”即足以让新设备取得 E2EE 数据访问能力。这是明确接受的 Demo 安全折中；Device Registry、Device Key 和 envelope version 必须保留，以便后续升级到强 enrollment 时无需重做整个数据平面。

### 11.6 Compute Node Routing

Device Registry 负责回答“哪个设备可以执行这项任务”。

```text
Mobile
  ↓ 查询本账号 Device Registry
Desktop A: online, local_ai + local_mcp, default
Desktop B: offline, local_ai
Phone:     online, no_mcp
  ↓
选择 target_device_id = Desktop A
  ↓ 用 Desktop A public key 加密 Job
Cloud Relay 只按 account_id + target_device_id 路由 ciphertext
```

已确认默认策略：

- 一个 Account 同一时间最多只有一台 Default Compute Node；
- AI、MCP 和后台执行第一版统一默认路由到该节点，不按 capability 分别维护多个默认节点；
- 请求可以临时选择其他满足 capability 的 trusted compute node；
- 服务端必须验证 target device 属于同一 account 且未 revoked；
- capability 不满足时拒绝路由；
- 默认节点离线时只允许排队、用户手动选择其他节点，或用户明确授权改用 Lifly Cloud AI；
- 严禁因为本地节点离线而自动把明文改投 Cloud AI；
- 设备撤销后不再接收新 Job，也不再获得新的 key envelope。

### 11.7 Session / Token / 云端入口

所有云端入口必须绑定 authenticated subject：

- legacy migration endpoints；
- sync credentials；
- sync push；
- device registry / enrollment / revoke；
- key envelopes；
- AI relay jobs；
- Cloud AI consent token；
- MCP/API token。

客户端不能提交任意 `user_id` 让服务端信任。服务端从认证 session 推导 `account_id/user_id`，并对 `device_id` 做归属和状态校验。

Access token / refresh token / device credential 必须可撤销；客户端秘密保存在 Secure Secret Store，不进入 SharedPreferences 或业务 SQLite 明文字段。

Auth secret 与 E2EE secret 分离。

### 11.8 已冻结的 Demo 账号/设备产品规则

以下产品决策已确认，Demo 阶段不继续扩张：

1. 仅手机号作为 Account Identity；底层 Account ID 使用不可变 UUID，手机号不作为业务表主外键；
2. 暂不做短信验证码，未注册手机号可以直接注册；正式公开服务前必须补手机号持有证明；
3. 密码不得以明文上传云端，认证协议优先采用成熟 OPAQUE/aPAKE；禁止把固定客户端哈希当长期认证协议；
4. Demo 不做 Recovery Key；忘记密码联系管理员处理 Account 凭据，但管理员无权解密历史 E2EE 数据；
5. 新设备密码认证成功后自动 enrollment，直接取得 Password Key Envelope 并恢复 ADK；不做二维码、旧设备批准和强设备校验；
6. Device Registry 现在就实现，用于设备管理、能力声明和手机到 Personal Compute Node 的路由；
7. 一个 Account 同时只允许一台 Default Compute Node，其他计算节点仍可手动选择；
8. Default Compute Node 离线时绝不自动切换到 Lifly Cloud AI，必须由用户明确选择等待、其他设备或授权 Cloud AI；
9. Demo 只做基础设备 revoke；Emergency Revoke、ADK rotation 和渐进重加密延后 Hardening；
10. 第一版不引入邮箱、Apple/Google/GitHub/微信等其他身份，但 Account Identity 模型保留未来扩展空间。

### 11.9 Demo 阶段明确后置的账号能力

为了尽快达到可演示闭环，以下能力不阻塞 Demo：

- 短信验证码 / 手机号真实持有证明；
- 自助更换手机号；
- 自助忘记密码；
- Recovery Key；
- 新设备二维码/旧设备批准；
- Emergency Revoke / ADK rotation；
- CAPTCHA、复杂风控和异常登录分析；
- 自助账号注销完整工作流；
- OAuth / 邮箱 / 第三方身份。

Demo 期间忘记密码或账号异常由管理员处理。管理员允许重置 Account 认证状态，但没有 E2EE 数据恢复能力；若还有已持有 ADK 的设备，可由客户端重新包装 Password Key Envelope，否则旧密文不可恢复。

密码修改如果在 Demo 阶段实现，必须先在客户端持有旧 ADK 的情况下完成新 Password Key Envelope 重包装，再提交认证凭据变更，避免出现“密码改成功但数据永久解不开”的半完成状态。

### 11.10 OPAQUE 实施门禁

OPAQUE/aPAKE 属于安全关键模块，不在 Dart/Python 中自行实现密码协议。v0.8.4 第一项技术工作必须先验证维护中的 RFC 9807 实现能否以一个小型 Crypto/Auth Adapter 接入 Flutter Android/Windows，并与服务端互操作。

目标模块边界：

```text
Flutter AuthRepository
        ↓
OpaqueClientAdapter
        ↓
维护中的 RFC 9807 implementation

FastAPI Auth module
        ↓
OpaqueServerAdapter
```

Web 可以后续使用独立 WASM/JS adapter；不能为了 Web 同构而阻塞 Android + Windows Demo。若现有库集成不可接受，应重新评估 Demo 身份方案，而不是临时自创 PAKE。

## 12. Android / Mobile 收口

在 E2EE 开发同时解决真实手机安装阻塞：

- 正式 application id；
- 正式 app label / icon；
- release INTERNET permission；
- release signing；
- Secure Secret Store platform adapter；
- 加密 DB 初始化；
- 首次 E2EE onboarding；
- 简化 device enrollment / device management UI；
- Cloud AI consent UI；
- Personal Compute Node 状态 UI。

Android local notification adapter、reminder permission / scheduling 归入 `v0.9.0` 功能补全版，因为真实系统提醒属于路演主链路，不能留到纯视觉/稳定性收口阶段。

## 13. Web 特殊边界

Web 不能简单照搬 native secure storage 假设。

需要单独验证：

- WebCrypto non-extractable device key；
- IndexedDB/OPFS 数据库加密；
- 浏览器设备 enrollment；
- logout / clear site data；
- XSS 对解密后内存数据的风险；
- 是否允许“记住本设备”；
- 不支持的浏览器必须显式降级，而不是无声关闭 E2EE。

## 14. 与 Demo 版本计划的关系

本文件不再独立拆分 `v0.8.4 ~ v0.8.9`。E2EE、账号、Device Registry、AI Provider、Personal Compute Node 与 Cloud AI privacy boundary 统一作为 `v0.9.0` 功能补全版的技术子计划执行。

总版本计划以以下文件为准：

```text
doc/plan/demo-feature-completion.md   -> v0.9.0
doc/plan/roadshow-release.md          -> v0.9.1
```

其中：

- `v0.9.0` 完成真实功能闭环：Demo Account、Device Registry、E2EE 数据平面、附件/Audit 加密、真实 PowerSync、Ollama/AI Provider、Personal Compute Node、Cloud AI selective disclosure、Android 真机系统能力以及阻塞 Demo 的产品消费层遗留；
- `v0.9.1` 原则上不再新增底层能力，只做 UI/UX、真机稳定性、演示脚本、隐私证据、性能和路演主线收口；
- 短信验证码、Recovery Key、设备强审批、复杂风控、正式计费等 production hardening 继续进入后续 backlog，不阻塞当前路演目标。

本文件负责回答“这些安全/AI 技术能力应该如何实现”，不再回答“分别属于几个版本”。

## 15. 测试与门禁

必须新增跨阶段 release gate：

### Crypto tests

- encrypt/decrypt round trip；
- ciphertext nondeterminism；
- AAD tamper detection；
- wrong key fails closed；
- key version migration；
- device revoke；
- Password Key Envelope recovery；
- Recovery Key tests 在正式 Hardening 启用后再加入；
- plaintext migration；
- no key in logs/storage/preferences。

### Cloud blindness tests

自动检查 server-side rows / MinIO objects：

```text
不能 grep 到测试 memo 正文
不能看到测试 merchant
不能看到测试 task title
不能看到 AI prompt
不能看到附件明文
```

### AI privacy tests

- self-host path cloud relay receives ciphertext only；
- Desktop Node offline 不自动降级到 Cloud AI；
- Cloud AI 未 consent 返回拒绝；
- consent scope 外字段不得发送；
- inference logs 不包含 payload；
- candidate action 未经客户端 commit 不产生业务实体。

### Auth isolation tests

- user A 不能读/写 user B envelope；
- user_id spoof 无效；
- revoked device 不能获取新 key envelope；
- revoked API token 失效；
- sync credentials 必须绑定 authenticated user。

### Mobile tests

- release APK 能联网；
- encrypted DB 能启动/重开；
- 系统提醒真实投递；
- logout/clear device 正确销毁本地 key material；
- app 数据恢复不能导致 secret/key 错配。

## 16. 不做的捷径

禁止：

- 为了 E2EE 自己发明密码算法；
- 把 ADK 存服务器“方便找回”；
- 把 ADK/API Key 放 SharedPreferences；
- 只做数据库磁盘加密就宣称 E2EE；
- 服务端为了搜索偷偷保存明文 title/tags/amount；
- Cloud AI 获得用户长期解密密钥；
- Cloud AI 默认上传全部生活数据；
- Desktop Node 不在线时静默改送 Cloud AI；
- 日志/trace 保存 prompt 或 response；
- 只加密正文，却让 audit / attachment / AI session 泄露同样内容。

## 17. 完成定义

整个计划完成后应能真实证明：

```text
1. Lifly 云数据库和对象存储只有 ciphertext + 必需同步 metadata。
2. Lifly 运维人员无法从云存储直接恢复用户备忘、账单、任务、AI 会话和附件。
3. 用户自己的 Desktop Node 可在云端不可见内容的情况下完成 AI/MCP 执行。
4. 使用 Lifly Cloud AI 前，用户清楚看到发送范围，并主动授权。
5. Cloud AI 不获得 ADK，不保存业务 payload，返回后由客户端本地提交。
6. Android 真机可以安全安装、联网、离线记录、提醒、E2EE 同步并使用两种 AI 路径。
7. Demo 阶段新设备可通过密码认证自动恢复 Password Key Envelope；服务端本身不能恢复用户数据；正式版再升级受信设备批准 / Recovery Key。
```
