# AI 交互与混合输入解析

## 1. 目标

AI 交互不是普通聊天，而是把用户自然语言转化为结构化生活数据。

核心能力：

```text
一句话 → 多个动作 → 预览/确认 → 写入 → 审计 → 可撤销
```

## 2. 混合输入

必须支持混合输入：

```text
今天中午食堂花了18，晚上8点提醒我改页面，记一下今天有点累。
```

解析为：

- expense_create；
- task_create；
- memo_create。

## 3. 意图类型

第一版支持：

```text
memo_create
journal_create
expense_create
task_create
task_complete
expense_search
expense_summary
memo_search
task_list
```

## 4. 解析策略

解析分两层：

### 4.1 LLM 解析

负责理解自然语言，包括：

- 时间；
- 金额；
- 商户；
- 任务；
- 情绪；
- 备忘内容。

### 4.2 规则校验

负责确定：

- 金额是否合法；
- 时间是否能解析；
- 分类是否存在；
- 是否需要用户确认；
- 是否存在重复账单；
- 是否可能误删。

## 5. 确认策略

### 5.1 低风险

直接执行，支持撤销：

- 新建备忘；
- 新建普通账单；
- 新建普通任务。

### 5.2 中风险

执行后提示用户检查：

- 金额较大；
- 时间模糊；
- 分类置信度低；
- CSV 批量导入。

### 5.3 高风险

必须确认：

- 删除；
- 批量修改；
- 批量导入 commit；
- 修改历史账单；
- 清空任务；
- 覆盖导入。

## 6. AI 回复格式

AI 写入成功后，回复必须包含：

```text
已完成：
- 已记账：餐饮 18 元，商户：食堂
- 已创建提醒：今天 20:00 改页面
- 已记录日记：今天有点累

回复“撤销”可撤销本次操作。
```

## 7. 解析失败

当解析置信度低时，AI 不应强行写入。

示例：

```text
我不确定你是要记账还是备忘。你可以确认一下：
1. 记一笔 18 元账单；
2. 记录一条备忘；
3. 两者都做。
```

## 8. 时间处理

所有时间必须包含：

- 原始表达；
- 解析后时间；
- timezone；
- 是否推断。

字段示例：

```json
{
  "raw_time": "晚上8点",
  "parsed_time": "2026-06-21T20:00:00+08:00",
  "timezone": "Asia/Shanghai",
  "is_inferred": true
}
```

## 9. 金额处理

金额必须包含：

- amount；
- currency；
- direction；
- confidence。

## 10. 分类处理

分类不确定时使用 category_hint，并由后端映射到已有分类。无法匹配则使用“未分类”。

## 11. 审计

AI 每次操作必须记录：

- 原始输入；
- 解析结果；
- 调用工具；
- before snapshot；
- after snapshot；
- request_id；
- actor_type = ai。

## 12. 聊天式 AI Capture

当前核心能力是：

```text
capture_parse → capture_commit → capture_undo
```

客户端体验应从“调试式表单”升级为聊天式捕获，但底层边界不变：

```text
用户输入一轮内容
    ↓
服务端解析候选动作
    ↓
客户端展示确认卡片
    ↓
用户选择提交
    ↓
写入业务表、audit_logs、undo token
```

本地模式下，`PowerSyncCaptureStore.captureParse` 已具备最小规则拆分能力：普通记录会降级为 `memo_create`，包含提醒语义会生成 `task_create`，包含金额消费语义会生成 `expense_create`。这只是离线可用的规则地基，不等于完整 AI 推理；后续仍需扩展更多金额、日期、商户、任务标题和多轮上下文边界。

当前基础会话模型：

```text
McpCaptureSession
  capture_id
  user_id
  original_text
  timezone / locale
  actions[]
  requires_confirmation
  session_status: parsed / committed / failed / dismissed / expired
  source_channel
  expires_at
  committed_at / dismissed_at
  created_at / updated_at

McpCaptureTurn
  id
  capture_id
  turn_index
  role: user / assistant / system
  text
  actions[]
  selected_action_indexes[]
  result_entities[]
  turn_status: parsed / committed / failed / undone / partial
  source_channel
  created_at / updated_at
```

本地 Local Core 已接入 `captureParse` / `captureCommit` / `captureUndo`。本地模式下候选动作、确认结果、undo token 与 undo 结果会写入 PowerSync 本地表；commit 创建的业务实体会写入 `source_capture_id`，便于会话恢复和撤销追踪。

## 13. 附件和语音输入边界

附件参与解析时只传资产引用，不把附件内容塞进用户文本：

```text
asset_ids[]
asset_context[]
```

语音输入拆成两层：

```text
录音或上传音频 Asset
STT 转文本后进入 CaptureTurn
```

没有 STT 能力前，客户端可以展示语音入口占位，但不能伪装成已完成语音识别。AI Capture 手机端体验默认应自动判断类型，不要求用户先选择“备忘 / 任务 / 记账”。
