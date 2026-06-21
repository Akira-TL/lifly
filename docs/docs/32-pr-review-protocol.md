# 32. PR Review Protocol

## 1. PR 必填

```text
关联 Issue
变更摘要
变更文件
验证方式
风险
是否更新文档
是否影响架构冻结项
```

## 2. Review Checklist

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

## 3. 必须拒绝的 PR

- Android 通知监听；
- AI 直接写数据库；
- CSV 直接写账单；
- 附件二进制写 PostgreSQL；
- 删除用户数据不走 trash/tombstone；
- 新增 MVP 外模块；
- 本地 MCP 直接写 SQLite；
- 修改架构冻结文档但没有 ADR。
