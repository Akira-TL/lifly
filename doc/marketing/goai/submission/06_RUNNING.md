# Lifly GOAI 运行说明

这份说明只保留评委真正需要的路径。完整开发文档仍在 `doc/`。

## 1. 最快体验：生产 Web

打开：

```text
https://lifly.babelbeast.com/
```

后端健康检查：

```text
https://lifly.babelbeast.com/api/v1/health
```

Web 是 Flutter release 静态构建，由 Nginx 直接托管；它不是 Flutter debug web-server。

## 2. 本地开发

需要：Docker、Node.js/pnpm、Python 3.12+ 与 `uv`、Flutter。需要演示 Personal Compute Node 时还要安装 Ollama 和一个可用模型。

```bash
pnpm install
docker compose -f infra/docker-compose.yml up -d
pnpm dev
```

服务端默认开发端口和正式端口约束见 `doc/architecture/port-allocation.md`。

## 3. 生产 Web 构建

```bash
bash scripts/web-release-build.sh
```

输出：

```text
build/public-web
```

默认使用：

```text
LIFLY_DATA_MODE=api
LIFLY_API_BASE_URL=https://lifly.babelbeast.com/api/v1
```

## 4. Android / Windows

Android release：

```bash
bash scripts/android-release-build.sh
```

正式 Android 包需要本地 keystore，并通过签名验证。

Windows 必须在真实 Windows host 上执行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows-release-build.ps1
```

WSL 构建不能作为 Windows release 成品。

## 5. 可验证工程入口

```bash
bash scripts/check-v0.9.0-release-gate.sh
bash scripts/check-v0.9.0-delivery-gate.sh
bash scripts/run-v0.9.0-golden.sh
```

`run-v0.9.0-golden.sh` 会检查真实 OPAQUE、Desktop Local MCP 的加密写入、认证 API、加密 Compute Node Job、host Ollama、Candidate commit、encrypted audit 和 undo。

## 6. 当前演示边界

- Demo 账号阶段不依赖短信验证码。
- Recovery Key 尚未作为完成能力提交。
- 完整 Google / Apple Calendar 接入属于后续方向。
- Personal Compute Node 离线不会自动把原本的本地 AI 明文请求切给 Cloud AI。
- Cloud AI 使用 Selective Disclosure；用户确认后才发送本次任务所需的最小上下文。
