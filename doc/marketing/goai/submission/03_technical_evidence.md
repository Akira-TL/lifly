# Lifly GOAI 技术证据

这份材料不负责“讲好听”，只负责让评委能快速确认几件事：项目确实能跑，AI 确实能调用工具，用户数据的边界不是靠口头承诺，出错以后也有办法追踪和撤销。

## 1. 先看这几份文档

如果评委想继续往下看工程实现，优先给这些入口：

- `doc/architecture/architecture-overview.md`
- `doc/design/ai-interaction.md`
- `doc/api/mcp-contract.md`
- `doc/architecture/local-mcp-desktop.md`
- `doc/architecture/sync-and-offline.md`
- `CONTEXT.md`

Lifly 的业务写入大致是：

```text
Phone / Web / Desktop / External Agent
        ↓
Candidate Actions / MCP Tools
        ↓
业务校验与确认
        ↓
Local Core Commit
        ↓
Audit / Undo
        ↓
E2EE Sync
```

Personal Compute Node 的路径是：

```text
请求设备
  ↓ 设备间加密任务
Cloud Relay
  ↓
Trusted Desktop Compute Node
  ↓
Ollama / OpenAI-compatible Provider + Local MCP
  ↓
候选动作 / 加密结果
```

## 2. AI 和模型怎么接

当前工程里有三类 Provider 路径：

- Ollama：用户自己的 Desktop Node 可以本地运行；
- OpenAI-compatible：用户可以自行配置兼容接口；
- Lifly Cloud AI：只有经过本次 Selective Disclosure 后才处理必要上下文。

另外保留 deterministic parser / validator 作为兜底和校验层。

无论使用哪个 Provider，模型都不直接获得“改数据库”的能力。AI 先返回结构化候选动作，业务层再决定它能不能提交。

提交材料里如果提到具体模型，要写实际演示时使用的模型名称和版本，不只写“Ollama”。

## 3. MCP 怎么证明

Cloud MCP 和 Local MCP 使用同一套业务语义。

可给评委看的证据包括：

- MCP tool list；
- Hermes / OpenClaw / 自建 Agent 的一次真实调用日志；
- 一次 `task_create`、`expense_create` 或 capture 的 request / result；
- 一次重复投递或失败场景，证明工具边界不是只处理 happy path。

外部 Agent 不直接连数据库。它拿到的是 Lifly 暴露出来的工具。

## 4. E2EE 不要只写在 PPT 上

最有用的是下面几类证据。

### 云端看不到业务正文

创建一条专门用于验证的 Memo / Expense / Task，同步后直接查服务端存储。应该能看到 encrypted envelope，但查不到测试正文、金额描述或任务内容的业务明文。

### AI Relay 看不到 Job 正文

Relay 需要知道目标设备、任务状态和密文 envelope，但不应该持有 Job 的解密密钥或业务明文。

### Cloud AI 需要本次授权

Selective Disclosure 页面应显示：

- 发给哪个 Provider；
- 这次要发送哪些数据；
- 为什么需要；
- 授权只针对当前任务。

Cloud AI 不获得 ADK，也不会因此得到账号级长期解密能力。

### 本地节点离线时不偷偷换云端

Default Compute Node 下线以后，本地请求应该返回 unavailable / retry。只有用户主动改选 Cloud AI 并确认发送范围后，才走云端路径。

## 5. 可以直接引用的工程脚本

仓库已有：

- `scripts/check-v0.9.0-release-gate.sh`
- `scripts/check-v0.9.0-delivery-gate.sh`
- `scripts/run-v0.9.0-golden.sh`
- `scripts/android-release-build.sh`
- `scripts/web-release-build.sh`
- `scripts/windows-release-build.ps1`
- `scripts/assemble-desktop-demo-bundle.sh`

如果要给评委附日志，不需要把所有测试输出都塞进去。保留和参赛主线直接相关的几份即可：

```text
evidence/
  release-gate.log
  delivery-gate.log
  golden-runtime.log
  android-signature.txt
  windows-build-info.txt
  server-ciphertext-proof.txt
  relay-ciphertext-proof.txt
  screenshots/
```

## 6. 当前已经确认的交付状态

- 项目版本基线是 v0.9.0；
- 仓库里已有 Linux Desktop / Compute Node Demo 构建目录和 release / delivery 脚本；
- Web release 已通过 `scripts/web-release-build.sh` 生成；
- `https://lifly.babelbeast.com/` 当前可以返回 Lifly Web 首页；
- `https://lifly.babelbeast.com/api/v1/health` 当前返回 v0.9.0 health OK；
- 最终 APK、Windows ZIP、PDF、PPTX 仍需要整理到正式提交目录；
- `scripts/demo-reset.sh`、`scripts/demo-health.sh`、`scripts/check-v0.9.1-roadshow-gate.sh` 目前还没有，这些留到复赛演示稳定性阶段再补。

## 7. 最短运行说明应该写什么

不要把整套开发文档直接甩给评委。`RUNNING.md` 只需要回答：

```text
需要什么系统和依赖
怎么填环境变量
怎么启动
Demo 用哪个账号
Ollama 用哪个模型
各服务应该看到什么 health
怎么跑 Golden Demo
有哪些已知的宿主机限制
```

评委应该照着几步命令就能知道入口在哪里，而不是先研究整个 monorepo。
