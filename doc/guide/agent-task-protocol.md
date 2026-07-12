# Lifly Agent Task Protocol

## 1. 目的

本协议定义 AI agent 如何领取、执行、交付 Lifly 任务。

## 2. 任务开始前

Agent 必须读取：

```text
doc/archive/v0.1.0plan/architecture-freeze.md
当前 Issue
相关文档
```

Agent 必须确认：

```text
任务目标
允许修改的文件
禁止事项
验收标准
是否需要测试
```

## 3. 执行中规则

- 小步提交
- 不混合无关修改
- 不自行扩展需求
- 修改 schema 必须同步测试
- 修改行为必须同步文档

## 4. 不确定时

如果不确定，Agent 应停止扩大实现，并在 Issue/PR 中写明 Assumption 或标记 needs-architecture-decision。

## 5. 提交前检查

提交前必须确认：

```text
lint/test/analyze 通过，或说明未运行原因
新增行为有测试
文档已更新
没有破坏架构冻结项
没有泄露密钥
```

## 6. 输出格式

Agent 最终回复或 PR 描述必须包含：

```text
Summary
Changed Files
Validation
Risks
Follow-ups
```
