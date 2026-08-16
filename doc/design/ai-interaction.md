# AI 交互与执行模型

## 1. 目标

Lifly AI 不是普通聊天层，而是把用户自然语言转化为**结构化候选动作**，再由客户端 Local Core 完成正式业务写入。

核心链路：

```text
输入
  ↓
选择执行目标
  ↓
解析 / 推理
  ↓
Candidate Actions
  ↓
用户查看 / 修改 / 确认
  ↓
Local Core commit
  ↓
Audit + Undo + E2EE Sync
```

AI Provider、Personal Compute Node、Lifly Cloud AI 都不能直接获得业务数据库写权限。

## 2. 混合输入

必须支持一段输入拆成多个动作：

```text
今天中午食堂花了18，晚上8点提醒我改页面，记一下今天有点累。
```

可以产生：

```text
expense_create
task_create
memo_create
```

候选动作可以来自规则引擎、本地 Compute Node 或 Lifly Cloud AI，但最终提交语义必须一致。

## 3. Candidate Action

Candidate Action 是 AI 推理结果，不是业务事实。

第一阶段核心动作包括：

```text
memo_create
journal_create
expense_create
task_create
asset_register_external_url
```

搜索、摘要、任务列表等 read action 可以继续存在，但不能绕过 Local Core / 本地 read model 的数据访问边界。

Candidate Action 必须：

- 有固定 schema/version；
- 通过客户端 validator；
- 不能携带未定义任意 SQL / tool invocation；
- 修改后产生明确 revised state；
- commit 后返回结果实体和 undo token。

## 4. 三类执行目标

AI 页面需要明确显示当前执行位置，不能把不同隐私边界隐藏成一个“AI”按钮。

### 4.1 本机规则

```text
用户输入
  ↓
Local Core deterministic parser / validator
  ↓
Candidate Actions
```

特点：

- 不需要云端推理；
- 可离线；
- 能力有限但结果可预测；
- 同时作为 Provider 输出的安全 fallback / validator 基础。

### 4.2 Personal Compute Node

用户可以把任务发送给同一 Account 下受信任的 Desktop Compute Node：

```text
Requester Device
  ↓ device-to-device encryption
Cloud Relay
  ↓ ciphertext only
Desktop Compute Node
  ↓ decrypt
Ollama / OpenAI-compatible Provider
  ↓
Candidate Actions
  ↓ encrypt result
Requester Device
```

UI 必须显示目标设备，例如：

```text
My PC · Ollama
```

Compute Node 不可用时必须显示 unavailable / retry，不允许自动转 Lifly Cloud AI。

### 4.3 Lifly Cloud AI

Cloud AI 是显式选择性披露通道：

```text
本地准备必要上下文
      ↓
Cloud AI Disclosure
      ↓ 用户确认
发送本次必要明文
      ↓
Lifly Cloud AI
      ↓
Candidate Actions
```

Cloud AI 不获得 ADK，也不能持续读取用户 E2EE 数据。

## 5. Cloud AI Disclosure

在发送明文之前，UI 至少要表达：

```text
发送目标
发送的数据范围
为什么需要发送
本次授权是否只生效一次
```

第一版可以只支持 `once` 授权。

禁止：

- 因 Personal Compute Node offline 自动同意 Cloud AI；
- 把整个账户历史无差别发送；
- 将 prompt / context / response 写入普通 DB、analytics、trace payload 或常规日志；
- 把 ADK、Device private key 或用户 Provider API Key 发给 Cloud AI。

## 6. 解析与验证分层

### 6.1 AI Provider / Planner

负责理解：

- 时间；
- 金额；
- 商户；
- 任务；
- 情绪；
- 备忘内容；
- 上下文中的修正意图。

### 6.2 Deterministic Validator

负责确定：

- action schema 是否合法；
- 金额是否合法；
- 时间是否能解析；
- 必填字段是否完整；
- 是否需要用户确认；
- 是否可能误删或覆盖；
- Provider malformed output 是否应 fail closed。

Validator 与 Local Core 不应被 Provider 替代。

## 7. 确认策略

确认策略按业务风险决定，而不是按 Provider 来源决定。

### 7.1 低风险

可以支持快速执行，但必须可撤销：

- 新建普通 Memo；
- 新建普通账单；
- 新建普通 Task。

### 7.2 中风险

应明确提示用户检查：

- 金额较大；
- 时间模糊；
- 低置信度分类；
- 多动作混合输入；
- Provider 对原输入做了较大推断。

### 7.3 高风险

必须显式确认：

- 删除；
- 批量修改；
- 批量导入 commit；
- 修改历史账单；
- 清空任务；
- 覆盖导入；
- Cloud AI Disclosure。

## 8. 连续 AI Capture

核心会话模型：

```text
create session
  ↓
append user turn
  ↓
append assistant candidate turn
  ↓
revise action
  ↓
commit turn
  ↓
undo turn
  ↓
continue session
```

Session 是连续会话容器；Turn 是 commit / revise / undo 的最小状态单元。

### 8.1 Session

```text
McpCaptureSession
  capture_id
  user_id
  original_text
  timezone / locale
  actions[]
  requires_confirmation
  committed
  session_status
  source_channel
  expires_at
  committed_at / dismissed_at
  created_at / updated_at
  revision
```

`committed` 只表示历史中至少执行过一轮，不代表会话终止。

### 8.2 Turn

```text
McpCaptureTurn
  id
  capture_id
  turn_index
  role
  text
  asset_ids[]
  asset_context[]
  actions[]
  selected_action_indexes[]
  result_entities[]
  undo_token
  supersedes_turn_id
  turn_status
  source_channel
  created_at / updated_at
  revision
```

修改候选动作创建 revised turn，并保留 `supersedes_turn_id` 版本链；不覆盖历史。

已经执行的 turn 如需修改，应先撤销旧结果，再创建新的 revised candidate，避免旧实体和新设置同时存在。

## 9. Candidate Commit 的唯一业务路径

无论 Candidate 来自哪个执行目标，最终都通过客户端 Local Core 提交：

```text
Candidate Action
   ↓
LocalCoreExternalAiActionCommitter
   ↓
Capture parse / revise
   ↓
Capture commit
   ↓
Local Core business write
   ↓
Audit + Undo
   ↓
EncryptedSyncStore
```

这条 seam 保证：

- Provider 不直接写数据库；
- Cloud AI 与 Compute Node 不产生不同业务语义；
- AI 写入与用户手工写入共享 revision / tombstone / audit；
- AI 结果能够撤销。

## 10. 撤销与修改

AI 执行成功后必须提供：

- 创建/修改了哪些实体；
- undo token；
- 修改入口；
- 撤销结果。

撤销不能删除会话历史。历史 Turn 继续保留，用于解释“AI 当时做了什么”。

Undo 的业务效果仍通过 Local Core 进入正常生命周期，例如创建实体转为 `ai_trashed`，并产生新的 E2EE revision。

## 11. AI 回复与展示

UI 应优先展示结构化结果，而不是只输出一段自然语言：

```text
已识别 3 个动作

账单
餐饮 · ¥18 · 食堂

任务
20:00 改页面

备忘
今天有点累
```

每个动作需要清楚区分：

```text
待确认
已执行
已修改
已撤销
失败
```

执行目标也要可见：

```text
本机规则
My PC · Ollama
Lifly Cloud AI
```

工程术语如 X25519、ADK、Relay 不应直接暴露给普通用户主界面；隐私详情页可以解释更深层边界。

## 12. 解析失败

当输入或 Provider 输出不可靠时，不强行写入。

例如：

```text
我不确定这是要记一笔 18 元账单，还是只记录成备忘。请选择要执行的内容。
```

Provider unavailable、timeout、malformed output、invalid action 都必须进入明确错误或安全 fallback，而不是构造看似成功的假 Candidate。

## 13. 时间处理

时间语义至少需要：

```text
raw expression
parsed datetime
timezone
is_inferred
```

示例：

```json
{
  "raw_time": "晚上8点",
  "parsed_time": "2026-06-21T20:00:00+08:00",
  "timezone": "Asia/Shanghai",
  "is_inferred": true
}
```

跨设备 Job 必须保持 Requester 的 timezone / locale 语义，不能由 Desktop 所在系统时区静默重解释。

## 14. 金额与分类

金额 action 至少包含：

```text
amount
currency
direction
confidence
```

分类不确定时可以使用 category hint / suggested classification，但最终映射和有效性检查属于客户端业务规则，不应由 Provider 自由创建不可控分类事实。

## 15. Audit

AI 每次正式操作都需要可追踪：

```text
actor_type = ai
source channel
execution target
entity type / id
action
request / capture correlation
before / after semantic history
```

`source_text / before_snapshot / after_snapshot` 属于敏感 payload，不能作为云端 plaintext audit history。它们必须进入 E2EE audit entity 或仅保留在受保护本地存储中。

## 16. 附件输入

附件输入使用两层引用：

```text
asset_ids[]       稳定 Asset 引用
asset_context[]   本轮解析能力和快照
```

`asset_context` 必须明确能力状态：

```text
ready
unsupported
needs_pdf_text_extraction
needs_ocr_or_vision
needs_speech_to_text
needs_external_content_fetch
error
```

没有真实解析能力时不得伪装成 ready。

附件本身保持 Asset E2EE；发送给 Personal Compute Node 或 Cloud AI 前，必须按对应执行目标的权限和 Disclosure 规则决定是否解密、发送哪些内容。

## 17. 语音输入

语音拆成：

```text
Audio Asset
  ↓ STT
Text
  ↓
Capture Turn
```

没有 STT 能力时可以显示入口和能力状态，但不能伪造识别结果。

## 18. E2EE 同步

AI Capture 的 Session、Turn、original text、actions、result entities、undo token 都属于业务敏感 payload。

v0.9.0 正式同步路径：

```text
Local Capture projection
       ↓
EncryptedSyncStore
       ↓
encrypted_entities
       ↓ PowerSync
Other Device
       ↓ decrypt/materialize
Local Capture projection
```

旧 plaintext `mcp_capture_sessions / mcp_capture_turns` 云端接口只能作为兼容 surface，不能成为新的默认依赖。

## 19. 隐私不变量

AI 交互必须持续满足：

- Provider 只产出 Candidate，不直接写业务库；
- Personal Compute Node Relay 看不到 Job 明文；
- Compute Node offline 不自动 Cloud fallback；
- Cloud AI 必须明确 Disclosure；
- Cloud AI 不获得 ADK；
- Candidate 最终在 Requester / 用户客户端 Local Core 提交；
- Audit 敏感 payload 保持 E2EE；
- AI Job、Cloud prompt、API Key 不进入普通日志。

## 20. 当前 v0.9.0 验收重点

实机需要证明：

1. 用户可看到并选择 AI 执行目标；
2. Default Desktop Compute Node 能真实使用 Ollama；
3. Requester 与 Desktop encrypted Job 可跨语言互操作；
4. Relay 服务端只能看到 ciphertext 和路由 metadata；
5. Desktop offline 时不会自动使用 Cloud AI；
6. Cloud AI 必须经过本次授权；
7. Candidate 可以修改、提交和撤销；
8. 提交后 Memo / Ledger / Task 走 Local Core E2EE write seam；
9. 重复投递不会重复创建业务实体；
10. AI Capture 会话可以跨设备 E2EE 恢复。
