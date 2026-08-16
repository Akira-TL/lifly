# Lifly

**Lifly = Life + Fly.**

Lifly 是一个 Personal Life Agent。它想做的不是让人更认真地“管理生活”，而是把重复的管理动作尽量拿掉：消费记录、临时任务、提醒、备忘、账单整理，都可以从自然语言、截图、账单文件或用户自己的 Agent 进入同一套生活数据系统。

AI 的结果不会直接变成业务事实。Lifly 先生成 Candidate Actions，再经过校验、确认和 Local Core 提交；已执行动作可以留下审计记录，并在支持的路径上撤销。

## Online Demo

生产 Web：

```text
https://lifly.babelbeast.com/
```

API health：

```text
https://lifly.babelbeast.com/api/v1/health
```

当前版本基线：`v0.9.0`。

## What is in Lifly

- Memo：备忘、随手记录、AI 分类与标签。
- Ledger：手动记账、支付宝/微信账单导入、预览、重复检测、transfer/中性流水处理。
- Task & Reminder：任务、提醒策略、预警与系统通知。
- AI Capture：一句自然语言可以拆成 Memo / Ledger / Task 候选动作。
- Cloud MCP / Local MCP：Hermes、OpenClaw 或其他 Agent 可以通过受控工具调用 Lifly。
- Personal Compute Node：用户自己的 Desktop 可以运行 Ollama、Local MCP 和后台执行器，手机通过加密任务调用。
- Local-first + E2EE Sync：核心数据在本地保持可用，跨端同步使用加密数据面。
- Selective Disclosure：需要 Cloud AI 时，只在用户明确授权后发送当前任务所需的最小上下文。

## Repository

```text
apps/client_flutter       Flutter Web / Android / Desktop client
services/api              FastAPI backend, Cloud MCP and relay APIs
services/local-mcp        Local MCP / Compute Node worker
packages/local-core       Controlled local business execution boundary
packages/protocol         Shared protocol and crypto contracts
infra                     PostgreSQL / Redis / MinIO / PowerSync / Nginx
scripts                   Build, release, delivery and golden-demo gates
doc                       Product, architecture, API and competition docs
```

正式文档入口：[`doc/README.md`](doc/README.md)。

## Local Development

```bash
pnpm install
docker compose -f infra/docker-compose.yml up -d
pnpm dev
```

更完整的开发、端口和运行约束请看：

- `doc/guide/development.md`
- `doc/architecture/port-allocation.md`
- `doc/architecture/architecture-overview.md`
- `doc/api/mcp-contract.md`

## Release Builds

Web production bundle：

```bash
bash scripts/web-release-build.sh
```

Android release：

```bash
bash scripts/android-release-build.sh
```

Windows release 必须在真实 Windows host 构建：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows-release-build.ps1
```

核心工程门禁：

```bash
bash scripts/check-v0.9.0-release-gate.sh
bash scripts/check-v0.9.0-delivery-gate.sh
bash scripts/run-v0.9.0-golden.sh
```

## License

Lifly 第一方代码采用 **PolyForm Noncommercial License 1.0.0**。

允许查看源码、fork、修改和非商业使用/分发；重新分发时必须保留许可证和项目提供的 `Required Notice`。**商业使用需要另行取得授权。**

第三方依赖仍分别遵守各自许可证，详见对应依赖清单和构建产物中的 notices。

See [`LICENSE`](LICENSE) and [`doc/legal/open-source-commercial.md`](doc/legal/open-source-commercial.md).
