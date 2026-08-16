# Lifly GOAI 初赛提交清单

## 今天一定要有

### 1. 项目介绍

文件：`01_project_introduction.txt`

已经按报名页使用场景写好，重点是问题、解决方式、当前进展和源码开放边界，不塞过多架构名词。

### 2. Proposal PDF / PPTX

建议文件名：

```text
Lifly_GOAI_2026_Proposal.pdf
Lifly_GOAI_2026_Proposal.pptx
```

B3 / Living Paper · Life Fly 继续作为视觉母版。

内容顺序可以保持在 16–20 页左右：

1. Lifly = Life + Fly
2. 为什么生活管理本身也成了负担
3. Lifly 是什么
4. 一句话变成 Memo / Ledger / Task
5. 自己的 Agent 怎么通过 MCP 接进来
6. 邮件、截图和账单怎么进入 Lifly
7. 手动账本和导入账单怎么避免重复
8. 微信 / 支付宝 transfer / 中性流水
9. Task / Reminder Strategy
10. Memo / Ledger / Task / Assets / Overview
11. Personal Compute Node
12. Local-first / E2EE
13. Candidate / Audit / Undo
14. Phone / Web / Desktop / Agent 的分工
15. 一天里的真实使用方式
16. 工程架构与可验证证据
17. 当前进展、开放边界和后续计划
18. 结尾

不必为了页数硬凑内容。

### 3. 在线 Web

提交地址：

```text
https://lifly.babelbeast.com/
```

当前生产 Web 使用 Flutter release 静态产物，由 Nginx 直接托管。提交前再跑一次：

```bash
bash scripts/web-release-build.sh
curl -I https://lifly.babelbeast.com/
curl https://lifly.babelbeast.com/api/v1/health
```

### 4. 项目介绍填入报名系统

不要只把 txt 放 ZIP 里，报名页字段本身也要填完整。

## 有现成成品就一起交

### Android

```text
Lifly-v0.9.0-android-release.apk
android-signature.txt
```

APK 应该是 signed release，并保留 `apksigner` 验证结果。

### Windows

```text
Lifly-v0.9.0-windows-x64.zip
```

Windows 包必须来自真实 Windows host 构建，不拿 WSL/Linux bundle 改名。

### 工程说明

平台允许附件较多时，可以附：

```text
RUNNING.md
TECHNICAL_EVIDENCE.md
OPEN_SOURCE_AND_COMPLIANCE.md
```

## 视频这轮不赶

初赛的 submission requirements 把 prototype / video 列为 optional，所以今天不为了视频牺牲 PDF、PPT 或生产 Web。

赛道同时要求可演示或等价的可验证材料。我们这一轮用在线 Web、可安装构建包和工程证据承担这件事。

如果晋级复赛，Demo / Demo Video 就会变成需要认真补齐的材料。

## License 怎么交代

当前准备采用：

```text
PolyForm Noncommercial 1.0.0
```

意思是第一方源码可以被查看、fork、修改和非商业分发；商业使用需要另行授权。

比赛材料里的准确说法：

```text
Source-available for non-commercial use.
Commercial use requires separate authorization.
```

不要写成 MIT / Apache，也不要写“完全开源”。因为商业用途受到限制，它不属于 OSI 定义下的 Open Source。

正式 `LICENSE` 落库前还需要确定著作权主体在 Required Notice 中的写法，并核对第三方依赖。

## One-pager

One-pager 就是一页项目摘要，通常是一张 A4 或一页大画布。

它适合放：

- 一句话定位；
- 用户问题；
- 一张产品 / Agent 流程图；
- 三四个最重要的产品画面；
- 为什么和普通聊天机器人不同；
- Demo / Repo 链接或二维码；
- 联系方式。

它不是初赛必交项。GOAI 总决赛会要求 one-page project summary，晋级以后再做。

## demo-reset

`demo-reset.sh` 是内部演示工具。

它把专门的 Demo 账号恢复到一个固定起点，例如：

```text
清掉上一轮演示新建的数据
清掉 pending candidate / 临时 AI Job
恢复固定示例 Memo / Ledger / Task
恢复默认 Compute Node / Demo 设置
```

这样同一条演示可以连续跑很多次，不会被上一次留下的数据干扰。

它绝对不能碰真实用户数据。初赛不用补，复赛做现场 Demo 前再实现。

## 复赛再补的东西

- `demo-reset.sh`
- `demo-health.sh`
- `check-v0.9.1-roadshow-gate.sh`
- Demo 视频或备用录屏
- 最终 Third-party Notices
- 更完整的 RUNNING.md
- One-pager
- 答辩 FAQ
- 一套可重复导入的脱敏 Demo Dataset

## 推荐提交目录

```text
Lifly_GOAI_2026_Preliminary/
├── 00_README_FIRST.pdf
├── 01_Project_Introduction.txt
├── 02_Lifly_GOAI_Proposal.pdf
├── 03_Lifly_GOAI_Proposal.pptx
├── 04_Builds/
│   ├── android/
│   │   ├── Lifly-v0.9.0-release.apk
│   │   └── signature.txt
│   └── windows/
│       └── Lifly-v0.9.0-windows-x64.zip
├── 05_Engineering/
│   ├── RUNNING.md
│   ├── TECHNICAL_EVIDENCE.md
│   └── evidence/
├── 06_License/
│   ├── OPEN_SOURCE_AND_COMPLIANCE.md
│   └── THIRD_PARTY_NOTICES.md
└── 07_Links/
    ├── web_demo.txt
    └── source_repository.txt
```

如果平台只允许少量文件，就先交项目介绍、Proposal PDF/PPTX 和在线 Web 地址。构建包与工程附件按上传能力再加。
