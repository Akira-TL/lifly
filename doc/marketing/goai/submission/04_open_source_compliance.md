# Lifly GOAI 开放复用、隐私与合规说明

## 1. 开放复用方向

Lifly 当前长期方向是：

```text
客户端 + MCP + 协议 + 本地模式：开放复用
官方云同步 / 存储 / 官方 AI 服务：可商业化运营
```

适合开放复用的工程部分包括：

- MCP tool schema；
- Local MCP；
- Agent / Candidate Action 业务协议；
- 本地优先数据模型；
- 导入导出格式；
- Personal Compute Node 相关本地组件；
- 客户端与技术文档（最终范围以许可证收口为准）。

## 2. 当前许可证状态

**不要在 GOAI 材料中写“已采用某许可证”，除非仓库正式加入对应 LICENSE 并完成依赖/IP 审核。**

当前候选方向：

- AGPL；
- Apache / MIT + 官方商业云；
- 双许可证。

初赛建议表述：

> Lifly 采用“核心能力开放复用 + 官方云服务商业化”的长期方向。当前正在完成最终许可证与第三方依赖边界收口；MCP 协议、本地能力、数据迁移与用户可导出原则会优先保持开放和可复现。

如果比赛平台要求必须填写明确 License，应在提交前完成一次独立法律/IP 决策，不要临时随意选择。

## 3. 用户数据所有权

Lifly 产品原则：

- 用户可以导出核心数据；
- 用户可以删除云端数据；
- 核心功能应支持本地模式；
- 不以用户数据锁定作为商业模式；
- Cloud AI 不获得账户级永久解密能力。

## 4. 数据授权边界

### External Agent

Hermes / OpenClaw / 自建 Agent 的邮箱、截图、第三方工具权限由用户自己配置和授权。

Lifly 不应宣传成“自动获得用户邮箱权限”；正确表达是：

> 用户已经授权的 Agent 可以读取相关内容，并通过 Lifly MCP 把明确选择的数据写入 Lifly。

### Cloud AI

Cloud AI 仅在用户明确 Selective Disclosure 后处理当前任务需要的最小上下文。

要求：

- 显示目标 Provider；
- 显示发送数据范围；
- 显示原因；
- 第一版授权可限定为 once；
- Cloud AI 不获得 ADK；
- 不形成账户永久明文读取能力。

### Personal Compute Node

用户自己的 Trusted Desktop 可以运行 Ollama / Local MCP / background executor。

设备间 AI Job 应以加密任务传输；云 relay 不持有解密密钥。

## 5. 财务数据边界

Lifly 是个人生活数据与记账管理工具，不应在本次比赛材料中描述为：

- 银行；
- 支付机构；
- 投资顾问；
- 自动交易平台；
- 银行级账户对账系统。

支付宝 / 微信账单能力当前重点是：

- 文件解析；
- 收入/支出/transfer 识别；
- preview；
- duplicate 检测；
- 用户确认；
- rollback。

## 6. AI 执行安全边界

核心原则：

```text
AI Reasoning
  ↓
Candidate Actions
  ↓
Validate / Review / Confirm
  ↓
Local Core Commit
  ↓
Audit / Undo
```

Provider / MCP / Cloud AI 不应被描述为可以绕过业务边界直接修改正式数据库。

## 7. 第三方依赖与模型披露

最终提交建议附一页简表：

| 类型 | 示例 | 用途 | 是否用户可替换/自托管 |
|---|---|---|---|
| Local model runtime | Ollama | Personal Compute Node 推理 | 是 |
| OpenAI-compatible provider | 用户自配 | 可选模型接口 | 是 |
| PowerSync | 同步基础设施 | 跨端同步 | 视部署配置 |
| Flutter | 客户端 | Web / Android / Desktop | 开源框架 |
| PostgreSQL / Redis / MinIO | 服务基础设施 | 元数据、队列、对象存储等 | 可自托管 |

最终版本应以真实 `package.json` / `pyproject.toml` / `pubspec.yaml` / Cargo 依赖为准生成 Third-party Notices，不要仅凭宣传页列依赖。

## 8. 比赛材料中的风险提示

建议在技术页脚或附录明确：

- Demo Security Profile 不等于最终生产级账号恢复/设备审批模型。
- Recovery Key 尚未作为完成能力宣传。
- 完整第三方 Calendar 生态属于后续方向。
- Open-source license 尚在最终收口阶段时应明确披露。
- 任何真实账单/邮箱演示都使用脱敏或 Demo 数据。
