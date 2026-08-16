# Lifly GOAI 源码开放、隐私与合规说明

## 1. 源码开放方式

Lifly 不打算允许第三方拿项目代码直接做商业产品，也不打算用 MIT / Apache 这类允许商业复用的宽松许可证。

当前准备采用的方向是：

```text
第一方源码：PolyForm Noncommercial 1.0.0
商业使用：需要单独获得 Lifly 著作权方授权
官方云服务：由 Lifly 自行运营或授权运营
第三方依赖：继续遵守各自原许可证
```

PolyForm Noncommercial 允许非商业使用、修改和分发，因此别人可以 fork、研究、修改，也可以在非商业前提下继续分享自己的版本。商业目的默认不在授权范围内。

为了保留原作者信息，正式发布时会在许可证旁加入 Required Notice。fork 或重新分发时，需要把许可证和该 Notice 一并保留。最终 Notice 中的著作权主体名称要在 `LICENSE` 正式落库前确认。

需要注意：因为我们限制商业用途，这种方式更准确的称呼是 **source-available / non-commercial**，不属于 OSI 对“Open Source”的定义。比赛材料中直接说明，不把两者混在一起。

## 2. 为什么这样选

我们希望代码能被看见、研究和改进，也愿意让个人开发者、学生和非商业项目 fork。但如果有人基于 Lifly 做收费 SaaS、付费客户端、商业集成或其他商业产品，需要先拿到单独授权。

这和 Lifly 自己未来提供官方云同步、存储或 AI 服务并不冲突：著作权方可以同时提供非商业源码许可和单独的商业许可。

## 3. 用户数据

Lifly 的产品边界不建立在“把用户数据锁在云端”上。

目前的原则是：

- 用户可以导出核心数据；
- 用户可以删除云端数据；
- 核心能力保留本地运行路径；
- Cloud AI 不获得账号级长期解密能力。

## 4. External Agent 的权限

Hermes、OpenClaw 或自建 Agent 是否能读邮箱、截图或调用第三方工具，由用户自己在对应 Agent 上授权。

因此材料里不要写“Lifly 会自动读取你的邮箱”。更准确的是：用户已经授权的 Agent 可以读取相关内容，再把用户允许的数据通过 Lifly MCP 送进来。

## 5. Cloud AI 的权限

Cloud AI 只有在用户明确确认 Selective Disclosure 后，才拿到当前任务需要的那部分上下文。

界面和协议应能说明：

- 数据发给谁；
- 发哪些内容；
- 为什么要发；
- 这次授权的范围。

Cloud AI 不获得 ADK，也不会因为一次授权得到整个账号的持续解密能力。

## 6. Personal Compute Node

用户自己的 Trusted Desktop 可以运行 Ollama、Local MCP 和后台执行器。

手机或 Web 发往 Desktop 的 AI Job 使用设备间加密；Cloud Relay 负责路由和状态，不持有业务明文的解密能力。

## 7. 财务数据怎么描述

Lifly 是个人生活数据和记账工具，不是银行、支付机构、投资顾问或自动交易平台。

支付宝 / 微信账单这部分，目前实际做的是：

- 文件解析；
- 收入、支出和 transfer / 中性流水识别；
- 导入预览；
- duplicate 检测；
- 用户确认；
- rollback。

不要把它包装成银行级账户自动对账。

## 8. AI 写入为什么要有中间层

Lifly 不让 Provider、MCP 或 Cloud AI 直接把推理结果当成正式业务数据。

```text
AI 输出
  ↓
Candidate Actions
  ↓
校验 / 查看 / 确认
  ↓
Local Core Commit
  ↓
Audit / Undo
```

这条边界同时解决两个问题：模型可能判断错，用户也可能临时改变主意。

## 9. 第三方依赖

最终提交包应该从真实依赖文件生成 Third-party Notices，而不是只在 PPT 里列几个熟悉的名字。

需要覆盖：

- Flutter / Dart；
- Python / FastAPI 相关依赖；
- Node / MCP 相关依赖；
- Rust OPAQUE helper；
- PowerSync；
- PostgreSQL / Redis / MinIO；
- Ollama 以及实际演示模型的许可证和使用说明。

第三方依赖继续遵守各自许可证，Lifly 的非商业许可证只覆盖我们有权许可的第一方代码。

## 10. 参赛材料里的已知边界

当前不要宣称：

- Recovery Key 已经完成；
- 完整 Google / Apple Calendar 生态已经接通；
- AI 直接记账的所有入口已经统一复用账单导入去重实现；
- Lifly 完全不依赖云端；
- Demo Security Profile 已经等同于最终生产安全模型。

真实账单、邮箱和个人信息只使用脱敏数据或专门的 Demo 数据。
