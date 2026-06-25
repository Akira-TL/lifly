# 54. MCP v0.1 Schema / Cloud Runtime / Smoke 覆盖审计

## 背景

`docs/08-mcp-design.md` 明确规定 MCP v0.1 tool schema 的 source of truth 是：

```text
packages/protocol/src/mcp/tool-schemas.ts
```

Local MCP 必须复用同一套 schema，不能私自新增工具或改变输入契约。因此在实现 Local Core Bridge 和 Local MCP 前，需要先审计当前协议包、Python Cloud MCP、后端 smoke、Flutter diagnostics 的覆盖状态。

## 工具清单对齐

当前 v0.1 工具清单如下：

```text
capture_parse
capture_commit
capture_undo
memo_create
memo_search
expense_create
expense_search
expense_summary
task_create
task_list
task_complete
asset_create_upload_url
asset_register_external_url
```

审计结果：

| Tool | protocol schema | Python FastMCP cloud_server | REST endpoint | backend smoke | integration test | Flutter diagnostics |
| --- | --- | --- | --- | --- | --- | --- |
| capture_parse | yes | yes | yes | yes | yes | no |
| capture_commit | yes | yes | yes | yes | yes | no |
| capture_undo | yes | yes | yes | yes | yes | no |
| memo_create | yes | yes | yes | yes | yes | yes |
| memo_search | yes | yes | yes | yes | yes | yes |
| expense_create | yes | yes | yes | yes | yes | yes |
| expense_search | yes | yes | yes | yes | yes | no |
| expense_summary | yes | yes | yes | yes | yes | no |
| task_create | yes | yes | yes | yes | yes | yes |
| task_list | yes | yes | yes | yes | yes | no |
| task_complete | yes | yes | yes | yes | yes | yes |
| asset_create_upload_url | yes | yes | yes | yes | yes | no |
| asset_register_external_url | yes | yes | yes | yes | yes | yes |

## 主要发现

### 1. 协议包与 Cloud runtime 工具名基本一致

`packages/protocol/src/mcp/tool-schemas.ts`、`services/api/app/modules/mcp/cloud_server.py`、`services/api/app/modules/mcp/router.py` 中的 v0.1 工具名一致。

这说明 Local MCP 可以先以 `packages/protocol` 为工具注册来源，不需要新定义工具清单。

### 2. 后端 smoke 覆盖完整

`scripts/smoke-mcp-v0.1.sh` 覆盖了完整 v0.1 主链路，包括：

```text
capture_parse / capture_commit / capture_undo
memo_create / memo_search
expense_create / expense_search / expense_summary
task_create / task_list / task_complete
asset_create_upload_url / asset_register_external_url
invalid input cases
```

该脚本可以作为 Local MCP smoke 的参考模板。

### 3. FastAPI integration test 覆盖完整

`services/api/tests/integration/test_mcp_v0_1_contract.py` 覆盖完整 REST MCP 契约，适合作为 Cloud MCP 回归基线。

Local MCP 后续至少需要建立独立 contract/smoke，避免只依赖 Cloud runtime 测试。

### 4. Flutter diagnostics 是最小 smoke，不是完整 MCP contract

`apps/client_flutter/lib/data/api/api_diagnostics.dart` 当前只覆盖：

```text
health
memo_create
memo_search
expense_create
task_create
task_complete
asset_register_external_url
```

未覆盖：

```text
capture_parse
capture_commit
capture_undo
expense_search
expense_summary
task_list
asset_create_upload_url
```

这是可接受的，因为 Flutter diagnostics 的目标是手动连通性诊断，不是完整 MCP contract test。不要把 Flutter diagnostics 当成完整 MCP 测试基线。

### 5. asset_create_upload_url 对 Local MCP 是特殊工具

`asset_create_upload_url` 在 Cloud MCP 中依赖对象存储或 local-dev storage key。Local MCP 离线模式下无法保证云端 presigned URL 可用。

Local MCP 第一阶段可以采取：

```text
返回 unsupported / pending
或只生成本地 asset metadata intent
```

但不能伪造云端 upload_url。

## Local MCP 实现约束

Local MCP 第一版必须满足：

```text
工具名来自 packages/protocol
输入校验复用 zod schema
handler 调 Local Core Bridge
不直接 SQL 写入
不开放 TCP 端口
独立 local smoke 覆盖主链路
```

第一阶段推荐先实现：

```text
health
memo_create
memo_search
expense_create
expense_search
expense_summary
task_create
task_list
task_complete
asset_register_external_url
```

第二阶段再接：

```text
capture_parse
capture_commit
capture_undo
asset_create_upload_url
```

但为了六提交计划中的 smoke 闭环，Local Core fake 可以先实现 capture fake 行为，Local MCP skeleton 可按最小方式暴露。

## 待修复 / 待增强

### A. Flutter diagnostics 覆盖说明需要保持清晰

Flutter diagnostics 是手动诊断，不应追求完整 MCP contract。后续可在设置页文案中明确：

```text
Cloud MCP Smoke：最小连通性检查
完整 MCP contract：以后端 smoke / integration test 为准
```

### B. Local MCP smoke 必须独立

新增：

```text
scripts/smoke-local-mcp-v0.1.sh
```

覆盖至少：

```text
local_mcp_health
memo_create
memo_search
expense_create
expense_search
expense_summary
task_create
task_list
task_complete
asset_register_external_url
invalid input
```

### C. Local Core fake 需模拟 audit/revision 位置

Fake 不必持久化 audit log，但返回类型应保留 source_channel、tool_name、created_entities、undo_token 等位置，避免后续真实 adapter 大改接口。

## 结论

当前 Cloud MCP v0.1 的工具清单、协议包、REST endpoint、后端 smoke 与 integration test 基本一致，可以开始实现 Local Core Bridge 与 Local MCP skeleton。

下一步应先实现：

```text
packages/local-core
```

再实现：

```text
services/local-mcp
```

不要先从 Flutter 或 Hermes 配置入手。
