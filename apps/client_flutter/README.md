# Lifly Flutter Client

Flutter 客户端当前处于真实 API 接入早期阶段。默认连接本机 Lifly API：

```bash
http://127.0.0.1:8210/api/v1
```

可以通过 `--dart-define` 覆盖：

```bash
flutter run \
  --dart-define=LIFLY_API_BASE_URL=http://127.0.0.1:8210/api/v1
```

Android 模拟器访问宿主机 API 时通常需要：

```bash
flutter run \
  --dart-define=LIFLY_API_BASE_URL=http://10.0.2.2:8210/api/v1
```

## 后端连接诊断

进入客户端「设置」页，可以手动执行：

```text
检查 Health
运行 MCP Smoke
```

其中 MCP Smoke 会通过真实 API 调用一组最小主链路接口：

```text
GET  /health
POST /mcp/memo/create
POST /mcp/memo/search
POST /mcp/expense/create
POST /mcp/task/create
POST /mcp/task/complete
POST /mcp/asset/register-external-url
```

这不是完整端到端测试，只用于确认 Flutter 客户端能够访问 Lifly API，并且 MCP v0.1 基础接口可用。

## 验证

```bash
flutter analyze
flutter test
```
