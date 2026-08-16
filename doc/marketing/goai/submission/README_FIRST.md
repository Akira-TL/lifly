# Lifly × GOAI 2026 初赛提交包

赛道：Boundless Agents  
项目：Lifly  
版本：v0.9.0

## Lifly 是什么

Lifly 来自 Life + Fly。

我们做它的原因很简单：生活已经够忙了，不该再花一遍时间整理生活。消费完再开记账软件补一笔，想到事情再切到日历里排时间，收到不同平台的账单再自己对一遍，这些都很琐碎。

Lifly 把备忘、账本、任务、提醒和 AI 放进同一份个人生活数据里。用户可以直接说一句话，也可以把截图、账单或已有 Agent 的处理结果交给 Lifly。AI 先生成候选动作，用户确认后才进入正式数据；需要时还能查看审计记录或撤销。

用户自己的电脑也可以成为 Personal Compute Node，在本机运行 Ollama 和 Local MCP。云端 AI 不是默认接管者，只有用户明确授权时才会拿到当前任务需要的最小信息。

## 今天提交什么

初赛不用把材料做得过重。优先准备：

1. `01_project_introduction.txt`：报名页项目介绍。
2. `Lifly_GOAI_2026_Proposal.pdf`：主阅读材料。
3. `Lifly_GOAI_2026_Proposal.pptx`：和 PDF 同内容，方便后续继续改。
4. 在线体验地址：`https://lifly.babelbeast.com/`。
5. Android / Windows 构建包：平台允许附加时一起放进去。
6. `03_technical_evidence.md`：作为工程证据或附录使用。

视频这轮不作为 P0。初赛提交表中原型和视频是可选项；我们用可访问的 Web、构建包和工程证据来证明项目不是概念稿。

## 评委应该很快看懂的几件事

### 生活管理可以少做一遍

用户不需要为了“记录生活”再做一次重复劳动。支付截图、账单文件、自然语言和外部 Agent 都可以成为输入。

### 自己已经在用的 Agent 可以直接接进来

Hermes、OpenClaw 或自建 Agent 可以通过 Cloud MCP 使用 Lifly；本地 Agent 则可以走 Local MCP。Lifly 不要求用户换掉现有 Agent。

### 用户自己的电脑可以参与计算

Desktop 可以注册为 Personal Compute Node。手机把加密任务发给自己的电脑，再由 Ollama / Local MCP 处理。

### AI 没有直接改数据库的特权

AI 输出先成为 Candidate Actions。确认、校验、提交、审计和撤销仍然走 Lifly 的业务边界。

### 隐私边界是可解释的

核心生活数据本地可用，跨端同步使用 E2EE。Personal Compute Node 离线时，不会静默把原本准备在本地处理的明文交给 Cloud AI。

## 在线 Web

生产 Web 使用 Flutter release 静态构建，由 Nginx 直接托管，不依赖 Flutter 开发服务器常驻。

当前地址：

```text
https://lifly.babelbeast.com/
```

API：

```text
https://lifly.babelbeast.com/api/v1
```

每次部署前都应重新执行 `scripts/web-release-build.sh`，否则 Nginx 指向的 `build/public-web` 不存在时，根路径会直接返回 404。

## License 方向

我们不打算允许别人拿 Lifly 的代码直接做商业产品。

Lifly 第一方代码采用 **PolyForm Noncommercial 1.0.0**：允许查看源码、fork、修改和非商业分发；商业使用需要单独获得授权。分发和 fork 需要保留许可证以及项目提供的 Required Notice，用来标明原项目和著作权归属。

这意味着 Lifly 更准确的说法是 **source-available / non-commercial**，而不是 OSI 定义下的“完全开源”。比赛材料里直接说明这一点，不绕词。

仓库根目录已加入正式 `LICENSE`，当前 `Required Notice` 使用公开身份 `Akira-TL`。第三方依赖继续遵守各自上游许可证。

## 暂时不要写进宣传材料的内容

以下能力目前不应该说成已经完成：

- Recovery Key；
- “完全不用云端”；
- “AI 只能本地运行”；
- Google / Apple Calendar 等完整第三方日历生态；
- 所有 AI 记账入口都已经复用同一套账单导入去重逻辑；
- 银行级跨账户自动对账。

也不要写用户量、营收、融资、性能数字这类没有真实数据支撑的内容。

## One-pager 是什么

One-pager 就是一页项目摘要。它不是缩短版 PPT，而是让一个第一次看到 Lifly 的人，在一页里知道：解决什么问题、产品怎么工作、最特别的地方是什么、现在做到哪里、从哪里体验。

通常一页 A4 或一张大画布就够，可以放一个主流程图、三四个产品截图、Demo / Repo 二维码和联系方式。

这不是今天初赛的必交项。GOAI 在总决赛材料里会要求 one-page project summary，晋级以后再做更合适。

## demo-reset 是什么

`demo-reset.sh` 是给我们自己演示用的，不是产品功能。

它的作用是把专门的 Demo 账号恢复到一个已知状态，例如清掉上一次演示创建的 Memo / Ledger / Task、待处理 Candidate、临时 AI Job，再恢复固定的示例数据。这样一条 Demo 可以连续演很多次，不会因为前一次留下的数据导致下一次出现“已经存在”“金额变了”之类的问题。

它不应该碰真实用户数据，也不是今天初赛要补的东西。复赛需要重复现场演示时再做。
