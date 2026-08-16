# Lifly GOAI 现场 Demo 脚本

这份脚本不是宣传片分镜，而是一条 3–5 分钟能重复跑通的真实产品路径。目标只有一个：让评委看到 Lifly 会把生活里的输入变成可检查、可执行、可撤销的数据，而不是停在聊天回答上。

## 0:00–0:20｜先说人话

画面：Lifly 首页，手机和 Desktop 都已登录。

可以这样开场：

> Lifly 来自 Life + Fly。我们不想让用户为了管理生活，再做一遍重复劳动。消费完不用再补记一笔，想到事情也不用自己去日历里排。能交给 Agent 做的，就让 Agent 做。

这里先别讲 E2EE、MCP、Compute Node。

## 0:20–1:00｜一句话，拆成三件事

输入：

> 今天中午食堂花了 28 元，晚上 9 点提醒我改比赛 PPT，顺便记一下今天有点焦虑。

展示：

- Lifly 识别出一笔支出、一个任务和一条备忘；
- 三项先以 Candidate Actions 出现；
- 用户检查后确认；
- 首页、记账、任务和备忘里的数据随之变化。

这里评委应该能看明白：AI 不是给了一段建议，而是真的进入了 Lifly 的业务流程。

## 1:00–1:40｜自己的 Agent 也能记账

先展示最容易理解的场景：把付款截图发给自己正在用的 Agent。

然后说明另一种方式：如果用户已经给 Hermes、OpenClaw 或自建 Agent 邮箱权限，它也可以按计划读取支付通知或账单，再调用 Lifly MCP。

流程可以画得很短：

```text
截图 / 邮件 / 账单
        ↓
用户自己的 Agent
        ↓
Lifly MCP
        ↓
账单候选 / 导入预览
        ↓
确认写入
```

要把权限边界说清楚：Lifly 不是偷偷读邮箱，邮箱权限仍在用户自己的 Agent 那边。Lifly 只接收对方主动通过 MCP 送进来的内容。

## 1:40–2:10｜避免多记一笔

先准备一条已经手动记过的账：

```text
午饭 ¥28 · 12:42
```

再导入包含同一笔业务流水的账单，让 Lifly 把它标成重复候选。

随后展示一笔平台之间的资金搬家：

```text
微信 -¥500
支付宝 +¥500
```

这类流水识别为 transfer / 中性交易，不作为新的收入或支出统计。

这里不要说成“银行级自动对账”。当前已经落地的是账单导入中的业务重复判断，以及 transfer / 中性流水识别；AI 直接 `expense_create` 的全部入口还没有统一复用这套去重链。

## 2:10–2:40｜任务和提醒不用自己画日程

输入：

> 周三前把 GOAI 材料交掉。

展示：

- Agent 创建 Task；
- Lifly 给出 Reminder Strategy；
- 用户确认提醒；
- 如果 Android 通知现场稳定，再展示真实系统通知。

一句话就够：

> 我只需要告诉它什么时候要做完，剩下的提醒不要再让我自己记。

完整 Google / Apple Calendar 接入还不是当前完成能力，现场只展示已经接通的 Task、Reminder Strategy 和 Reminder Delivery。

## 2:40–3:20｜手机用自己的电脑跑 AI

打开 Settings / Devices，让评委看到同一账号下的 Phone 和 Desktop。

说明 Desktop 被设为 Default Compute Node，并显示 Ollama provider。

然后从手机发起一次 AI 请求：

```text
Phone
  ↓ 加密任务
Cloud Relay
  ↓
Desktop Compute Node
  ↓
Ollama + Local MCP
  ↓ 加密结果
Phone
```

重点不是“远程控制电脑”，而是用户自己的电脑可以成为 Lifly 的 AI 计算节点。

## 3:20–4:00｜把隐私边界演出来

有时间就做下面这条：

1. 暂时让 Desktop Node offline；
2. 手机再发起 local AI 请求；
3. Lifly 显示 unavailable / retry；
4. 它不会自己改送 Cloud AI；
5. 用户主动选择 Cloud AI；
6. 界面显示这次要发送给谁、发送哪些内容、为什么需要发送；
7. 用户确认后再执行。

这比单独放一页“我们用了 E2EE”更有说服力。

最后快速点一下 Audit / Undo，让评委看到 AI 做过的动作还能追溯和撤回。

## 收尾

可以直接说：

> Lifly 想做的不是再加一个生活管理 App，而是把那些本来要自己反复整理、记录和记住的事情交给 Agent。用户保留最后的确认权，也保留自己的数据和计算节点。

## 现场准备

- 演示账号只放脱敏数据；
- 不要在屏幕上露出手机号、Token、API Key 或设备私钥；
- 本地 Ollama 模型提前加载；
- 手机和 Desktop 提前确认在同一账号下；
- Web、API、PowerSync、Compute Node 都先跑一遍 health check；
- 如果某一段受现场网络影响，就跳过，不要临时改数据库救场。

晋级复赛后再补 `demo-reset.sh` 和 `demo-health.sh`，让每次演示都能从固定状态开始。
