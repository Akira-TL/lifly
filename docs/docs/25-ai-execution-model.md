# 25. AI 执行模型

## 1. 核心原则

LifeCore 的开发执行者主要是 AI agent，因此项目管理不能依赖人类口头沟通、会议同步和隐性上下文。所有执行依据必须进入仓库。

AI agent 开始任务前必须读取：

```text
docs/26-v0.1-architecture-freeze.md
当前 Issue
相关模块设计文档
```

## 2. Issue 是任务合同

每个 Issue 必须包含：

```text
Goal
Context
Scope
Allowed files
Forbidden changes
Acceptance criteria
Validation
Related docs
```

Issue 没写的内容默认不做。

## 3. PR 是交付单元

每个 PR 必须说明：

```text
完成了什么
改了哪些文件
如何验证
是否影响架构冻结项
是否新增依赖
是否更新文档
```

## 4. AI 角色

```text
Architect Agent       架构维护与边界控制
Client Agent          Flutter 客户端
Backend Agent         FastAPI / PostgreSQL / PowerSync
MCP Agent             Cloud MCP / Local MCP
Sync Agent            同步与离线
Asset Agent           附件与对象存储
Import Agent          CSV 导入导出
QA Agent              测试与验收
DevOps Agent          Monorepo / CI / Docker
Docs Agent            文档同步与变更记录
```

## 5. 禁止行为

AI agent 禁止：

- 私自新增 MVP 模块；
- 绕过 MCP/API 直接让 AI 写数据库；
- 让 CSV 导入直接写账单正式表；
- 把附件二进制写进 PostgreSQL；
- 在 Android 做通知监听；
- 把 Local MCP 设计成 Android 服务；
- 删除 audit log；
- 物理删除用户数据而不走回收站/tombstone；
- 修改架构冻结项而不创建 ADR。
