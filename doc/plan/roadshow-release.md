# Lifly 路演版本计划

目标版本：`v0.9.1`

## 1. 版本定位

`v0.9.1` 是路演/比赛展示版本。它建立在 `v0.9.0` 功能封板之上，原则上不再新增新的底层产品能力，不再重构核心同步/加密/账号/AI 架构。

本版本唯一目标：让 Lifly 在真实设备和现场演示环境下稳定、清晰、快速地讲完核心故事。

进入 v0.9.1 前必须先完成 v0.9.0 Delivery Hardening：Android 的正式演示包必须是签名且经 `apksigner` 验证的 release artifact；Desktop Client 与 Compute Node Companion 必须从同一确定源码基线构建；Windows 路径必须在真实 Windows host 验证 Credential Manager、native OPAQUE DLL、SQLCipher 与 Companion，而不能以 WSL 结果代替。WSL Secret Service 缺失不得通过明文密钥 fallback 绕过。

## 2. 路演主线

固定一条 3~5 分钟可以完整走通的主流程：

```text
登录 Lifly
↓
首页快速看到今日状态
↓
输入：
“今天中午食堂花了18，晚上8点提醒我改比赛PPT，顺便记一下今天有点焦虑。”
↓
Lifly AI 拆成 Expense + Task + Memo
↓
展示当前执行位置：My PC / Ollama
↓
确认后写入
↓
首页、记账、任务、备忘立即变化
↓
“提醒改成9点”
↓
“刚才18其实是28”
↓
撤销其中一项
↓
展示 Audit / Undo
↓
切到隐私状态：云端只保存 ciphertext
↓
可选展示“授权 Lifly Cloud AI”流程
```

路演版任何改动都优先服务这条主线。

## 3. UI/UX 收口

### 3.1 首页

- 信息密度高；
- 第一眼展示真正需要关注的内容；
- attention / urgent / warning 使用稳定语义色；
- 预算/消费只保留紧凑可读的可视化；
- 最近活动不要卡片瀑布化；
- AI 执行/同步/设备状态只显示用户需要知道的状态。

### 3.2 Memo

- 高密度列表；
- 时间在条目内部；
- AI 分类/标签通过颜色和短标签呈现；
- 快速新建/编辑/删除/恢复无明显跳转摩擦。

### 3.3 Ledger

- 顶部统计紧凑；
- 分类、预算、趋势一眼可读；
- 新增账单和 AI 创建账单结果明显；
- 不让图表压过交易本身。

### 3.4 Task

- 继续使用纵向列表，不做传统四象限分区；
- 用颜色表达重要/紧急组合；
- 时间、提醒、预警状态在同一视觉单元内；
- 系统提醒状态真实可见。

### 3.5 AI

- 输入区是主角；
- 明确显示执行位置：`本机规则 / My PC · Ollama / Lifly Cloud AI`；
- candidate action 结构清晰；
- 修改、确认、撤销不隐藏；
- Cloud AI Disclosure 授权文案简洁但明确；
- 不堆工程术语给普通用户。

### 3.6 Settings / Devices / Privacy

路演需要展示但不喧宾夺主：

- 当前账号；
- Device Registry；
- Default Compute Node；
- AI Provider；
- E2EE 状态；
- 同步状态；
- Cloud AI 隐私说明。

## 4. 真机和现场稳定性

必须针对路演环境做：

- Android **signed release APK** 真机长时间使用，并记录签名验证结果；
- Windows/Desktop Client + Compute Node Companion 从同一 delivery bundle 启动并长时间运行；
- Wi-Fi 断开/恢复；
- Desktop Node 临时离线；
- Ollama 首次模型加载；
- API/PowerSync 重启；
- 重复点击/快速提交；
- App 后台/恢复；
- notification permission 拒绝/允许；
- 无网情况下手动记录不阻塞；
- 所有关键 Error State 有用户可理解的 retry。

不能依赖“现场网络一定稳定”。

## 5. 启动和性能

路演版重点测：

- 默认 Lifly Core 首屏；
- Android cold start；
- Web Core-first 启动；
- AI Chat 首次进入；
- 页面切换；
- 大量 Memo/Expense/Task 列表；
- Local Core overview；
- E2EE decrypt/materialize；
- Desktop Node 接 Job 到开始生成的额外开销。

复杂主题可以慢，但默认 Lifly Core 必须保持最快路径。

## 6. 演示数据与演示模式

允许准备可重复导入的 Demo Dataset，但不能在正常 UI 中伪造实时数据。

需要：

- 一个固定 demo account；
- 可重置的 encrypted demo dataset；
- 一条脚本恢复到演示初始状态；
- 一条脚本检查 API/PowerSync/Ollama/Desktop Node 是否 ready；
- 一条 delivery gate 固定 Web/Android/Desktop 的源码 commit、构建方式、签名/宿主阻塞状态；
- 演示数据明确与真实用户数据隔离；
- 不在产品代码写死比赛专用假统计。

建议新增：

```text
scripts/demo-reset.sh
scripts/demo-health.sh
scripts/check-v0.9.1-roadshow-gate.sh
```

运行/调试仍遵循项目约束，只通过 scripts。

## 7. 路演隐私证据

不仅“说 E2EE”，还要能展示证据：

- 一条测试数据同步后，在服务端只能看到 ciphertext；
- Cloud AI 未授权不能读取；
- Desktop AI Job relay 服务端只能看到 target_device_id / status / ciphertext；
- Provider 状态明确显示“数据是否离开设备”；
- Cloud AI 授权页面显示本次发送范围；
- Cloud AI 请求结束后没有业务 payload 持久化。

这些证据可以形成路演 PPT/演示里的技术可信度部分。

## 8. 路演文案与产品叙事

统一产品一句话：

```text
Lifly 是一个本地优先、端到端加密、可审计和可撤销的个人生活执行 Agent。
```

核心差异只讲四点：

```text
1. 不只是聊天：AI 能真实修改 Memo / Ledger / Task。
2. 不只是云 AI：用户自己的电脑和 Ollama 可以成为执行节点。
3. 数据默认 E2EE：云端同步不等于云端可读。
4. AI 行为可确认、可审计、可修改、可撤销。
```

避免路演时铺陈过多未来功能。

## 9. 明确禁止进入 v0.9.1 的内容

除非发现阻塞路演的缺陷，否则不新增：

- 短信验证码；
- OAuth / 第三方登录；
- Recovery Key；
- 设备扫码审批；
- 复杂风控；
- 正式计费；
- 多 workspace；
- 新业务大模块；
- 花哨主题市场；
- 与路演无关的大规模重构。

发现上述需求统一回填 backlog，不打断路演收口。

## 10. v0.9.1 完成定义

```text
1. Android 真机安装后能独立完成核心记录。
2. 手机 ↔ Desktop Node ↔ Ollama AI 闭环稳定。
3. 跨设备 E2EE 同步可现场演示。
4. Android 系统提醒真实工作。
5. Cloud AI 明确授权路径可演示。
6. 主要页面视觉和信息密度达到路演标准。
7. 整条主 Demo 路径可以连续重复执行，不依赖手工修数据库。
8. demo-reset / demo-health / roadshow gate 可重复运行。
9. 展示时没有明显 placeholder、假数据、开发端口/调试文案泄露。
10. 路演后可继续基于 v0.9.x 进入正式安全 hardening，而不是推倒 Demo 架构。
```
