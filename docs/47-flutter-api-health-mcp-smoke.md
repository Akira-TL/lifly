# 47. Flutter API health + MCP smoke 接入

## 背景

本切片对应 Flutter 客户端真实 API 接入的第一步。目标不是完整客户端功能，而是提供一个可手动验证的最小闭环：

```text
Flutter 客户端
  ↓
Lifly API /health
  ↓
MCP v0.1 REST endpoints
```

该切片不改变 MCP v0.1 后端协议面。

## 配置

客户端新增 `AppConfig.apiBaseUrl`，默认值为：

```text
http://127.0.0.1:8310/api/v1
```

可通过 Flutter dart-define 覆盖：

```bash
flutter run \
  --dart-define=LIFLY_API_BASE_URL=http://127.0.0.1:8310/api/v1
```

Android 模拟器访问宿主机 API 时可使用：

```bash
flutter run \
  --dart-define=LIFLY_API_BASE_URL=http://10.0.2.2:8310/api/v1
```

## 客户端入口

在「设置」页新增「后端连接诊断」卡片，包含：

```text
API Base URL
Health 状态
MCP Smoke 状态
检查 Health 按钮
运行 MCP Smoke 按钮
```

## MCP Smoke 覆盖范围

Flutter 端 `ApiDiagnosticsService.runMcpSmoke()` 会依次调用：

```text
GET  /health
POST /mcp/memo/create
POST /mcp/memo/search
POST /mcp/expense/create
POST /mcp/task/create
POST /mcp/task/complete
POST /mcp/asset/register-external-url
```

该 smoke 用于确认客户端能连上后端，以及 MCP v0.1 最小主链路可用。它不会替代后端 `scripts/smoke-mcp-v0.1.sh`。

## 测试策略

Flutter widget test 不直接访问真实网络。测试通过 `FakeApiClient` 注入 `/dashboard` 响应，避免首页自动请求导致 widget test 不稳定。

验证命令：

```bash
cd apps/client_flutter
flutter analyze
flutter test
```

后端 smoke 仍使用：

```bash
bash scripts/smoke-mcp-v0.1.sh
```
