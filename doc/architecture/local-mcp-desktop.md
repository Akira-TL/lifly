# Windows 本地 MCP 设计

## 1. 定位

Windows 本地 MCP 用于：

- 本地 Hermes；
- 本地模型；
- 离线 AI；
- 私有部署；
- 云端不可用时的兜底。

Android 不做 MCP Server。

## 2. 非目标

本地 MCP 不是默认路径。默认 AI 路径仍是 Cloud MCP。

本地 MCP 不应造成两套业务逻辑。

## 3. 传输

采用 stdio。

原因：

- 适合本地 Agent；
- 不暴露网络端口；
- 与 Hermes/OpenClaw 本地工具调用方式匹配；
- 安全边界更清晰。

## 4. 结构

```text
Hermes / Local Agent
        ↓ stdio MCP
Local MCP Server
        ↓
Local Core Bridge
        ↓
PowerSync SQLite
        ↓
网络恢复后同步云端
```

## 5. 工具 Schema

Local MCP 与 Cloud MCP 共用工具 schema。

禁止本地 MCP 私自增加不兼容工具。新增工具必须先进入 packages/protocol。

## 6. 数据写入

本地 MCP 写入必须：

- 走本地 Core Bridge；
- 写 audit log；
- 使用同一删除状态机；
- 创建同一类 entity；
- 保持 revision。

不允许直接 SQL 写入主表。

## 7. 离线 AI 场景

当用户有本地模型时：

```text
用户 → Hermes 本地 AI → Local MCP → 本地 SQLite
```

限制：

- 无法调用云端分类能力；
- 无法上传新附件到云端；
- 外部链接预览不可用；
- 恢复网络后同步。

## 8. 切换策略

Hermes/OpenClaw 可配置：

```text
优先 Cloud MCP
Cloud 不可用时切 Local MCP
```

或者：

```text
隐私模式固定 Local MCP
```

## 9. 安全

Local MCP 默认只监听 stdio，不开放 TCP 端口。若未来支持 HTTP local server，需要显式开启并绑定 localhost。
