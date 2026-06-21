# 31. Agent Task Protocol

## 1. 开始任务前

AI agent 必须读取：

```text
docs/26-v0.1-architecture-freeze.md
当前 Issue
相关 docs
```

必须确认：任务目标、允许修改的文件、禁止事项、验收标准、测试要求。

## 2. 执行中

- 小步提交；
- 不混合无关修改；
- 不自行扩展需求；
- 修改 schema 必须同步测试；
- 修改行为必须同步文档。

## 3. 不确定时

不要猜，不要扩大范围。在 Issue/PR 中写明 Assumption，必要时创建 `needs-architecture-decision`。

## 4. 提交前检查

```text
lint/test/analyze 通过，或说明未运行原因
新增行为有测试
文档已更新
没有破坏架构冻结项
没有泄露密钥
```

## 5. 输出格式

```text
Summary
Changed Files
Validation
Risks
Follow-ups
```
