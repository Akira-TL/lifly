# Lifly GOAI 初赛提交清单

## A. 必交

### A1. 项目介绍

文件：`01_project_introduction.txt`

内容必须回答：

- 目标用户是谁；
- 真实痛点是什么；
- Lifly 如何解决；
- 为什么不是普通 chatbot；
- 核心创新与差异；
- 当前进展；
- 开放复用方向。

### A2. Proposal PPT / PDF

最终建议同时提供：

```text
Lifly_GOAI_2026_Proposal.pdf
Lifly_GOAI_2026_Proposal.pptx
```

建议 16–20 页，不要求固定画幅；以 B3 / Living Paper · Life Fly 为视觉母版。

推荐页面结构：

1. Lifly = Life + Fly / 让 AI 真正参与生活
2. 用户不应该把生活管理变成第二份工作
3. 生活信息为什么天然碎片化
4. Lifly 是什么 / Personal Life Agent
5. 一句话 → Memo + Ledger + Task
6. Bring Your Own Agent / Hermes / OpenClaw / MCP
7. 邮件 / 截图 / 账单自动记账
8. 手动账本与自动账本的重复判断
9. 微信 / 支付宝 transfer / duplicate
10. Agent 自动任务与提醒
11. One Life Space：Memo / Ledger / Task / Assets / Overview / AI
12. Personal Compute Node
13. Local-first + E2EE
14. Candidate Actions / Audit / Undo
15. Phone / Web / Desktop / Agent 多端角色
16. A Day with Lifly
17. 工程架构与可复现性
18. GOAI Boundless Agents 对齐 / 未来计划 / 结尾

## B. 强烈建议随初赛一起交

### B1. 真实 Demo 视频

```text
Lifly_Demo_3min.mp4
```

最好 3–5 分钟，至少证明：

- 自然语言生成多种 Candidate Action；
- External Agent / MCP 工具调用；
- 一次记账自动化或账单导入；
- Personal Compute Node / Local AI；
- 隐私边界或 Audit / Undo；
- 至少两个端真实运行。

### B2. 构建包

如果上传大小允许：

```text
builds/
  Lifly-v0.9.0-android-release.apk
  Lifly-v0.9.0-windows-x64.zip
```

Android 必须是 signed release，并附签名验证记录。

Windows 必须来自真实 Windows host 构建，不用 WSL Linux bundle 冒充 Windows 成品。

### B3. 运行说明

```text
RUNNING.md
```

只写评委真正需要的最短路径：

- 系统要求；
- 依赖；
- 配置；
- 启动；
- Demo 账号；
- Ollama 模型；
- 预期结果；
- 已知限制。

### B4. 技术证据

```text
TECHNICAL_EVIDENCE.pdf / md
```

建议 3–6 页附录，包含：

- 架构图；
- MCP tool chain；
- E2EE ciphertext evidence；
- Compute Node relay；
- Candidate → Commit → Audit → Undo；
- release/golden PASS；
- Android notification。

## C. 复赛前必须准备，初赛有空间则一起交

### C1. 代码 / Repo

建议：

```text
SOURCE_REPOSITORY.txt
```

包含：

- Repo URL；
- 提交 SHA；
- 对应 v0.9.0 / competition tag；
- build instructions；
- sample data；
- runtime evidence。

如果暂不公开完整 repo，可明确提交可验证源码快照及开放计划；但要注意 GOAI 的开放复用评分，不建议只交完全不可验证的闭源二进制。

### C2. Open Source Plan / LICENSE

至少提供：

```text
OPEN_SOURCE_PLAN.md
```

最好在复赛前完成最终 License 决策和 Third-party Notices。

### C3. Demo reset / health

当前计划中建议但仓库尚缺：

```text
scripts/demo-reset.sh
scripts/demo-health.sh
scripts/check-v0.9.1-roadshow-gate.sh
```

这些不是今天提交的必要条件，但复赛/现场演示非常值得补。

## D. 可选加分材料

- `Lifly_Demo_90s.mp4`：评委快速观看版。
- `ONE_PAGER.pdf`：一页项目摘要，后续决赛官方也会要求 one-page project summary，可提前准备。
- `ARCHITECTURE.png/svg`：一张可单独传播的架构图。
- `PRIVACY_MODEL.pdf`：隐私 / E2EE / Selective Disclosure 一页图。
- `MCP_INTEGRATION.md`：给 Hermes / OpenClaw / 自建 Agent 的接入示例。
- `SAMPLE_DATA/`：脱敏支付宝/微信账单、Demo screenshots、示例自然语言输入。
- `CHANGELOG.md`：从早期版本到 v0.9.0 的关键工程演进。
- `TEAM.md`：团队简介、分工与联系方式；报名系统如果已有完整团队信息则不是必须。

## E. 推荐最终 ZIP 结构

```text
Lifly_GOAI_2026_Preliminary/
├── 00_README_FIRST.pdf
├── 01_Project_Introduction.txt
├── 02_Lifly_GOAI_Proposal.pdf
├── 03_Lifly_GOAI_Proposal.pptx
├── 04_Demo/
│   ├── Lifly_Demo_3min.mp4
│   └── Lifly_Demo_90s.mp4                 # optional
├── 05_Builds/
│   ├── android/
│   │   ├── Lifly-v0.9.0-release.apk
│   │   └── signature.txt
│   └── windows/
│       └── Lifly-v0.9.0-windows-x64.zip
├── 06_Engineering/
│   ├── RUNNING.md
│   ├── TECHNICAL_EVIDENCE.md
│   ├── ARCHITECTURE.pdf
│   └── evidence/
│       ├── release-gate.log
│       ├── delivery-gate.log
│       ├── golden-runtime.log
│       └── screenshots/
├── 07_Open_Source/
│   ├── OPEN_SOURCE_PLAN.md
│   ├── THIRD_PARTY_NOTICES.md
│   └── LICENSE                            # when finalized
└── 08_Links/
    ├── source_repository.txt
    └── web_demo.txt                       # only after Web root is verified
```

## F. 当前优先级

### P0 — 今天提交前

1. 最终 B3 内容定稿。
2. 生成稳定 PDF。
3. 生成同内容 PPTX。
4. 录制 3–5 分钟真实 Demo。
5. Android signed release APK。
6. Windows Demo ZIP / EXE bundle。
7. 把 `01_project_introduction.txt` 填入报名页面。

### P1 — 有剩余时间就补

8. Technical Evidence 3–6 页。
9. Android 签名验证 / release gate / golden log。
10. Repo / source snapshot 链接。
11. Open Source Plan。

### P2 — 晋级后

12. Web 公开 Demo 首页。
13. demo-reset / demo-health / roadshow gate。
14. 最终 LICENSE / Third-party Notices。
15. One-pager / 答辩 FAQ / 现场备份视频。
