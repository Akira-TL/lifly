# Lifly GOAI 3–5 分钟 Demo 脚本

目标：用一条真实、连续、可验证的生活工作流证明 Lifly 不是通用聊天机器人，而是能进入真实生活闭环的 Personal Life Agent。

## Demo 主线

### 0:00–0:25｜一句话定位

画面：Lifly 首页 / 手机 + Desktop 同屏。

讲述重点：

> Lifly = Life + Fly。我们不希望用户把更多时间花在“管理生活”上。Lifly 让自己的 Agent、自己的电脑和可选云 AI，在用户授权边界内自动整理、记录和提醒生活。

不要先讲架构名词。

### 0:25–1:05｜自然语言一次生成三种生活数据

输入：

> “今天中午食堂花了 28 元，晚上 9 点提醒我改比赛 PPT，顺便记一下今天状态有点焦虑。”

展示：

- AI 解析为 `expense_create` / `task_create` / `memo_create` Candidate Actions；
- 显示执行位置（My PC · Ollama / 本机 / Cloud AI）；
- 用户检查后确认；
- 首页、记账、任务、备忘同步发生变化。

评委要看到：不是回答，而是结构化行动闭环。

### 1:05–1:50｜用户自己的 Agent 自动记账

场景 A：把付款截图发送给自己的 Agent。

场景 B：Agent 定时读取用户已经授权的支付相关邮件/账单文件。

展示逻辑：

```text
Email / Screenshot / Statement
        ↓
User's Agent (Hermes / OpenClaw / custom)
        ↓
Lifly Cloud MCP
        ↓
Ledger Candidate / Import Preview
        ↓
Review / Commit
```

重点说明：

- 邮箱权限属于用户自己的 Agent，不是 Lifly 静默读取邮箱。
- Lifly MCP 是受控业务入口。
- 支付宝 / 微信账单支持专用 parser、preview、duplicate 检测和 rollback。

### 1:50–2:20｜重复记账与跨平台资金搬家

先手动存在一条：

```text
午饭 ¥28 · 12:42
```

再导入包含相同业务流水的账单，展示被识别为重复候选。

随后展示：

```text
微信 -¥500 → 支付宝 +¥500
```

识别为 transfer / 中性流水，不把自己的资金搬家重复计入收入/支出。

措辞边界：当前账单导入链已经会和已有 active 账本做业务重复判断；不要宣称所有 AI `expense_create` 入口已经完全复用同一套去重实现。

### 2:20–2:55｜日程和提醒不需要自己手画

输入：

> “周三前把 GOAI 材料交掉。”

展示：

- Agent 创建 Task；
- Lifly 生成 Reminder Strategy；
- 显示提前准备建议 / warning reason；
- 用户确认后提醒生效；
- Android 真实系统通知弹出（若现场稳定）。

核心话术：

> 你负责生活，Agent 负责记得。

当前边界：完整 Calendar 生态是后续方向；当前应展示 Task + Reminder Strategy + Reminder Delivery，不宣称 Google/Apple Calendar 已完整接入。

### 2:55–3:35｜Personal Compute Node

画面切到 Settings / Devices：

- 同一 Account 下的 Phone / Desktop Device；
- Desktop Compute Node capabilities；
- Default Compute Node；
- Ollama provider。

从手机发起 AI Job：

```text
Phone
  ↓ device-to-device encrypted job
Cloud Relay (ciphertext only)
  ↓
Desktop Compute Node
  ↓
Ollama + Local MCP
  ↓ encrypted result
Phone
```

强调：自己的电脑不是“远程桌面”，而是自己的 AI 计算节点。

### 3:35–4:10｜隐私与人类控制

快速展示：

- E2EE Sync；
- Cloud relay ciphertext；
- Candidate Action；
- Audit；
- Undo；
- Cloud AI Selective Disclosure。

建议现场做一次：

1. Desktop Node offline；
2. 手机请求 local AI；
3. 显示 unavailable / retry，而不是自动切到 Cloud AI；
4. 用户主动选择 Cloud AI；
5. 显示本次授权目标、范围、原因；
6. 再执行。

这是 Lifly 最有技术可信度的差异化演示之一。

### 4:10–4:30｜收尾

> Lifly 不是把 Memo、Ledger、Task 和 AI 放在一个 App 里。它希望让生活数据成为一份持续的个人上下文，让用户自己的 Agent 真正能安全地参与生活。Life, fly.

## 视频拍摄要求

- 全部使用真实产品运行画面，不用 Figma 假操作替代核心链路。
- 视频中至少出现 Phone + Desktop 两个真实端。
- 关键步骤加短字幕，不需要长篇旁白。
- 录制时遮挡手机号、Token、API Key、设备私钥、真实个人账单信息。
- 推荐 1080p / 30fps / H.264 MP4。
- 另准备 60–90 秒短版，适合评委快速扫材料。

## Demo 失败时的备份顺序

1. 现场真实运行。
2. 本地预录完整 Demo 视频。
3. 每个关键闭环保留独立短片：AI Capture / MCP 记账 / Compute Node / E2EE / Reminder。
4. 关键技术证据截图 + Golden / Gate 日志。

不要把“现场网络稳定”当作必要前提。
