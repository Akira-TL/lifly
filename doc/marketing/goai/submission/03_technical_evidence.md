# Lifly GOAI 技术与可验证证据清单

这份材料不是宣传文案，而是给评委快速验证“真的能跑、真的有边界”的工程索引。

## 1. 架构证据

建议提交包内附 1 张架构图，并在 README 中链接以下正式文档：

- `doc/architecture/architecture-overview.md`
- `doc/design/ai-interaction.md`
- `doc/api/mcp-contract.md`
- `doc/architecture/local-mcp-desktop.md`
- `doc/architecture/sync-and-offline.md`
- `CONTEXT.md`

核心链路：

```text
Phone / Web / Desktop / External Agent
        ↓
Candidate Actions / MCP Tool Contract
        ↓
Local Core controlled commit
        ↓
Audit / Undo
        ↓
E2EE Sync
```

Personal Compute Node：

```text
Requester Device
  ↓ device-to-device encryption
Cloud Relay (ciphertext only)
  ↓
Trusted Desktop Compute Node
  ↓
Ollama / OpenAI-compatible Provider + Local MCP
  ↓
Candidate Actions / encrypted result
```

## 2. 模型与 Agent 说明

当前可披露：

- Local AI：Ollama Provider。
- OpenAI-compatible Provider：可作为用户自配模型接口。
- Lifly Cloud AI：显式 Selective Disclosure 后的单次最小上下文推理。
- Deterministic parser / validator：作为安全验证与 fallback 层。
- Provider 不直接写业务数据库，只产生结构化候选动作。

Demo 默认推荐使用仓库 Golden 脚本指定的本地 Ollama 模型；提交材料中应写实际录制时使用的模型名称和版本，不要只写“Ollama”。

## 3. MCP / Tool Calling 证据

Cloud MCP 与 Local MCP 使用同一业务语义边界。

对外重点说明：

- Hermes / OpenClaw / 自建 Agent 可通过 MCP 调 Lifly。
- 外部 Agent 必须经过受控 MCP 工具，不直接接数据库。
- 关键写入包含 memo / ledger / task / capture 等生活动作。
- MCP 认证、Tool schema、Candidate Action、Audit / Undo 都有工程合同。

建议附：

- MCP tool list 截图或 JSON；
- 一次 Hermes/OpenClaw 调用 Lifly MCP 的真实日志；
- 一次 `task_create` 或 `expense_create` 的 request → result；
- 一次失败/重复投递的幂等证据。

## 4. E2EE / Privacy 证据

必须避免只写“我们采用 E2EE”。建议提供 4 个可验证证据：

### A. 云数据库明文不可见

创建测试 Memo / Expense / Task 后，查询服务端存储，展示 ciphertext envelope；搜索测试正文/金额/任务文本得不到业务明文。

### B. AI relay 只看到密文

展示 relay 记录中存在：

- target device
- status
- ciphertext / envelope metadata

但不存在 Job 明文。

### C. Cloud AI 明确授权

展示 Selective Disclosure UI：

- provider / target
- data scope
- reason
- once authorization

Cloud AI 不获得 ADK，也不获得账户永久解密能力。

### D. No silent fallback

Default Compute Node 离线：

- local request 返回 unavailable / retry；
- 不自动把明文发给 Cloud AI；
- 只有用户主动授权后才走 Cloud AI。

## 5. Release / Test Evidence

仓库已有：

- `scripts/check-v0.9.0-release-gate.sh`
- `scripts/check-v0.9.0-delivery-gate.sh`
- `scripts/run-v0.9.0-golden.sh`
- `scripts/android-release-build.sh`
- `scripts/windows-release-build.ps1`
- `scripts/assemble-desktop-demo-bundle.sh`

建议提交时生成一个 `evidence/` 目录：

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
    device-registry.png
    candidate-actions.png
    cloud-ai-disclosure.png
    android-reminder.png
    encrypted-sync.png
```

不要只附测试数量；优先附和比赛主叙事直接相关的 PASS 证据。

## 6. 当前交付事实与缺口

截至本次材料盘点：

- 项目版本基线为 v0.9.0。
- 仓库内存在 Linux Desktop / Compute Node Demo build 目录与 delivery/release 脚本。
- 未在项目提交目录中发现最终 APK / Windows ZIP / PDF / PPTX / MP4 成品。
- 公网 API `https://lifly.babelbeast.com/api/v1/health` 当前返回 v0.9.0 health OK。
- 公网根路径当前不是可用 Web Demo 首页，因此不要把 `https://lifly.babelbeast.com/` 直接提交为在线体验地址，除非先完成 Web 部署与复查。
- `scripts/demo-reset.sh`、`scripts/demo-health.sh`、`scripts/check-v0.9.1-roadshow-gate.sh` 当前尚未存在；它们不是初赛硬性材料，但对复赛/现场稳定演示很有价值。

## 7. 最小可复现说明应包含

即使初赛不强制源码，建议准备：

```text
Platform requirements
Docker / Node / pnpm / Python uv / Flutter / Ollama
Environment variables
Startup scripts
Demo account preparation
Expected ports
Expected model
Health checks
Golden demo command
Known host-specific limitations
```

复现说明必须写“可运行路径”，不要让评委自己从完整开发文档中猜启动方式。
