# Lifly Domain Context

- **Account**：Lifly 云端识别的用户身份，承载登录、云服务权益和 Device Registry；Account 身份本身不赋予业务数据解密能力。
- **Device**：属于某个 Account 的客户端实例，拥有独立设备身份；设备是否能解密 E2EE 数据由其加密授权状态决定。
- **Trusted Device**：当前获得账号 E2EE 数据访问能力的 Device。Demo Security Profile 下，密码认证成功即可自动 enrollment；未来生产安全配置可升级为现有设备批准、Recovery Key 或更强设备验证。
- **Device Registry**：Account 下设备及其信任状态、能力和路由状态的目录；用于授权和任务路由，不保存设备私钥或业务解密密钥。
- **Desktop Client**：桌面端 Lifly UI / 本地数据客户端。它可以与 Compute Node Companion 安装在同一台电脑，但不因为“运行在桌面”就自动声明 `local_ai / local_mcp / background_executor` capability。
- **Compute Node Companion**：与 Desktop Client 同一交付包中的独立本地运行时，拥有独立稳定 Device Identity，负责 Local MCP、Local AI 与 encrypted relay worker 生命周期；v0.9.0 Demo 中允许依赖宿主 Node、uv 与 Ollama，但启动入口必须由交付 bundle 统一管理，不能要求开发者现场执行 `pnpm build`。
- **Personal Compute Node**：具有本地 AI、MCP 或后台执行能力、可承接其他设备加密任务的 Trusted Device；v0.9.0 Desktop 交付中由 Compute Node Companion 承担这一 Device 角色。
- **Default Compute Node**：Account 同一时间最多指定一台默认 Personal Compute Node；AI、MCP 和后台执行默认路由到该节点，其他 Trusted Device 仍可被用户临时选择；默认节点离线时不得自动把明文切换到 Cloud AI。
- **Account Data Key (ADK)**：用户业务数据的账户级数据密钥；与 Account 登录凭证独立，Lifly 云端不能由账号认证信息推导 ADK。
- **Password Key Envelope**：Demo Security Profile 下，用仅客户端可获得的密码认证导出密钥包装 ADK 的账户级 envelope；新设备密码认证成功后可直接恢复 E2EE 数据，服务端不获得该解包密钥。
- **Recovery Key**：未来生产增强能力；Demo Security Profile 暂不提供独立 Recovery Key，因此忘记密码且无任何已解密设备时无法恢复历史 E2EE 数据。
- **Device Enrollment**：设备取得账号 E2EE 数据访问能力的过程。Demo Security Profile 下，密码认证成功后自动 enrollment；未来可升级为现有 Trusted Device 批准、Recovery Key 或更强设备验证。
- **Normal Revoke**：用户主动移除仍受控设备的撤销方式；停止未来账号访问、同步和任务路由，但默认不触发紧急全量密钥轮换。
- **Emergency Revoke**：设备丢失或疑似泄露时的紧急撤销方式；立即停止未来访问和任务路由，并触发后续 ADK 轮换与渐进重加密。
- **Cloud AI Disclosure**：用户明确授权将本次推理所需的最小明文上下文发送给 Lifly Cloud AI 的行为；不授予云端持续解密用户数据的能力。
