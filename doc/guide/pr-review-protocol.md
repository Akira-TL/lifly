# Lifly PR Review Protocol

## 1. PR 目的

PR 是 AI agent 的正式交付单元。每个 PR 应对应一个 Issue。

## 2. PR 必填

每个 PR 必须包含：

```text
关联 Issue
变更摘要
变更文件
验证方式
风险
是否更新文档
是否影响架构冻结项
```

## 3. Review Checklist

Review Agent 应检查：

```text
是否超出 Issue 范围
是否违反架构冻结
是否新增未批准依赖
是否缺少 audit log
是否绕过 MCP/API
是否绕过 import_batch
是否把附件写入数据库
是否破坏删除状态机
是否缺少测试
```

## 4. 必须拒绝的 PR

以下 PR 必须拒绝：

- Android 通知监听
- AI 直接写数据库
- CSV 直接写账单
- 附件二进制写 PostgreSQL
- 删除用户数据不走 trash/tombstone
- 新增 MVP 外模块
- 本地 MCP 直接写 SQLite
- 修改架构冻结文档但没有 ADR

## 5. 合并条件

PR 可合并需要满足：

```text
CI 通过
测试通过或说明合理
文档同步
无架构冻结冲突
Issue 验收标准满足
```
