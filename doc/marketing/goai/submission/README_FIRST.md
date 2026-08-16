# Lifly × GOAI 2026 初赛提交包

赛道：Boundless Agents / 无界应用  
项目：Lifly  
版本基线：v0.9.0  
核心定位：Personal Life Agent / 个人生活执行 Agent

## 一句话

**Lifly = Life + Fly。让生活更轻，让 AI 真正参与生活。**

Lifly 不是另一个聊天机器人，而是一套隐私优先、跨设备、可本地运行的 Personal Life Agent：把备忘、记账、任务提醒、附件与 AI Capture 放进同一份持续的生活上下文，让用户自己的 Agent、自己的电脑和可选云 AI 都可以在明确边界内理解、整理和推进真实生活任务。

## 推荐提交顺序

初赛上传时，优先保证以下四项：

1. `01_project_introduction.txt`：报名页项目介绍，可直接粘贴。
2. 最终 `Lifly_GOAI_Proposal.pdf`：评委主阅读材料。
3. 同版 `Lifly_GOAI_Proposal.pptx`：方便后续复赛/答辩继续编辑。
4. `Lifly_Demo_3min.mp4`：强烈建议提交；用真实设备证明闭环，不以宣传片替代产品演示。

如果平台允许附加材料，再提供：

5. Android signed release APK。
6. Windows x64 Demo Bundle / EXE ZIP。
7. Web Demo URL（仅在 Web 首页已稳定部署后提供）。
8. `RUNNING.md` + `TECHNICAL_EVIDENCE.md`。
9. 代码仓库链接或源码归档（初赛可选，复赛应准备）。

## 评委 30 秒应该看到什么

- **真实场景**：用户不应该每天逐笔记账、手画日程、反复整理生活信息。
- **Agent 闭环**：自然语言 / 邮件账单 / 截图 → Agent → Lifly MCP → Candidate Action → 确认 → Memo / Ledger / Task → Reminder / Audit / Undo。
- **Bring Your Own Agent**：Hermes、OpenClaw 或用户自己的 Agent 可通过 Cloud MCP 使用 Lifly；本地 Agent 可通过 Local MCP 使用同一业务语义。
- **Personal Compute Node**：用户自己的 Desktop + Ollama 可以成为 AI 计算节点，手机通过加密任务调用。
- **隐私边界**：Local-first、E2EE Sync、Trusted Devices、Selective Disclosure；本地节点离线不会静默把明文切到 Cloud AI。
- **可审计执行**：AI 先产生 Candidate Actions，不直接写业务事实；动作可查看、确认、修改、审计和撤销。

## 官方初赛与后续准备

GOAI Boundless Agents 初赛核心提交是“项目介绍 + 提案 PPT/PDF”，原型或视频在提交表中列为可选；但赛道核心要求同时强调至少一个可演示、可验证的闭环任务，并要求 runnable demo、视频或等价验证材料。因此本项目按“**PDF/PPT + 真实 Demo 视频 + 可运行构建包**”标准准备，而不是只满足最低上传项。

复赛如果晋级，还需要更新方案、Demo、运行说明、代码或等价工程材料，因此本目录中的运行说明、技术证据和开源边界应从初赛开始维护，避免二次重做。

## 当前提交包尚需生成的二进制/媒体产物

- [ ] 最终 Proposal PDF
- [ ] 最终 Proposal PPTX
- [ ] 3–5 分钟真实 Demo 视频 MP4
- [ ] 60–90 秒短版 Demo（可选，用于快速审阅）
- [ ] Android signed release APK + `apksigner` 验证记录
- [ ] Windows x64 Demo Bundle / ZIP（真实 Windows host 构建）
- [ ] Web Demo 首页部署（当前只确认公网 API health 可用；未将 Web 根路径视为可提交 Demo）
- [ ] 最终源码仓库 URL / 源码快照
- [ ] 最终许可证或至少明确的 Open Source Plan

## 不应在材料中宣称

- Recovery Key 已完成。
- Lifly 完全不使用云端。
- AI 只能本地运行。
- 当前已经完成所有第三方日历生态接入。
- 当前所有 AI 记账入口均已完全复用账单导入的业务去重链。
- 已确定最终开源许可证（当前策略仍在 AGPL / Apache/MIT + 商业云 / 双许可证之间收口）。
- 虚构用户量、收入、融资、奖项或性能数据。
