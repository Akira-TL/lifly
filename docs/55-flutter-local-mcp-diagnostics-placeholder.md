# 55. Flutter Local MCP 状态占位

## 背景

`docs/53-local-core-bridge-foundation.md` 到 `docs/54-mcp-schema-implementation-audit.md` 已经明确：Local MCP 是 Windows / Desktop 本地 AI 与离线写入的未来入口，但当前 Flutter 客户端仍处于 Cloud API 直连模式。

为了避免测试阶段误判“已经支持本地离线写入”，本切片在设置页增加 Local MCP / 本地能力状态占位。

## 范围

修改：

```text
apps/client_flutter/lib/features/settings/settings_page.dart
```

新增卡片：

```text
本地能力 / Local MCP
```

展示：

```text
当前模式：Cloud API 直连
Local Core：已规划，未接入 Flutter
Local MCP：stdio skeleton，未由客户端启动
PowerSync：未启用
离线写入：未启用
```

## 非目标

本切片不做：

```text
Flutter 启动 Local MCP 进程
Flutter 调用 Local Core Bridge
PowerSync 接入
离线写入
Hermes 配置生成
系统托盘常驻
```

## 与现有诊断的关系

设置页已有：

```text
后端连接诊断
API Health
Cloud MCP Smoke
```

本切片新增的是本地能力状态说明，不替代 Cloud MCP smoke，也不执行 Local MCP smoke。

Local MCP smoke 仍通过命令行运行：

```bash
bash scripts/smoke-local-mcp-v0.1.sh
```

## 验收

```bash
cd apps/client_flutter
flutter analyze .
flutter test
```

最终全链路仍需：

```bash
pnpm --filter @lifly/local-core typecheck
pnpm --filter @lifly/local-mcp typecheck
bash scripts/smoke-local-mcp-v0.1.sh
bash scripts/smoke-mcp-v0.1.sh
```
