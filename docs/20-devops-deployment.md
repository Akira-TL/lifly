# 20. 部署、环境与 DevOps

## 1. 环境

至少支持：

```text
local
dev
staging
production
```

## 2. 本地开发依赖

```text
PostgreSQL
PowerSync
Redis
MinIO
FastAPI
MCP Server
Flutter
```

## 3. Docker Compose

开发环境使用 Docker Compose 启动：

- postgres；
- redis；
- minio；
- powersync；
- api；
- worker；
- cloud-mcp。

## 4. 配置管理

环境变量示例：

```env
DATABASE_URL=
REDIS_URL=
OBJECT_STORAGE_ENDPOINT=
OBJECT_STORAGE_BUCKET=
OBJECT_STORAGE_ACCESS_KEY=
OBJECT_STORAGE_SECRET_KEY=
JWT_SECRET=
MCP_SERVER_URL=
```

严禁提交真实密钥。

## 5. CI

CI 至少检查：

- Python lint；
- Python tests；
- TypeScript lint；
- TypeScript tests；
- Flutter analyze；
- Flutter tests；
- 数据库迁移检查；
- OpenAPI schema 生成；
- MCP tool schema 校验。

## 6. CD

MVP 可以手动部署。后续自动部署：

- API；
- Worker；
- MCP Server；
- PowerSync；
- 前端 Web，未来；
- 桌面/Android 构建产物。

## 7. 数据库迁移

使用 Alembic 管理 PostgreSQL 迁移。

迁移原则：

- 不直接改生产数据库；
- 每次迁移可回滚或有补救脚本；
- 大字段变更分阶段执行；
- PowerSync 相关表结构变更需单独验证。

## 8. 日志

日志必须包含：

- request_id；
- user_id hash；
- service name；
- error code；
- duration。

日志不得包含：

- API key；
- access token；
- 用户正文大段内容；
- 附件内容。

## 9. 备份

必须备份：

- PostgreSQL；
- 对象存储；
- 配置；
- 迁移脚本。

需要定期演练恢复。

## 10. 监控

MVP 关注：

- API 错误率；
- MCP 错误率；
- 同步失败率；
- 附件上传失败率；
- CSV 导入失败率；
- Worker 队列积压。

## 11. 分支、Tag 与提交规则

长期开发分支：

```text
develop/master
```

版本开发分支格式：

```text
develop/vx.x.x
```

示例：

```text
develop/v0.7.0
develop/v0.7.1
```

版本完成后：

```text
合并到 develop/master
打 tag：vx.x.x
保留必要分支用于追溯，后续可清理旧开发分支
```

提交信息格式：

```text
feat(module): 中文描述
fix(module): 中文描述
```

示例：

```text
feat(home): 实现首页概览聚合接口
fix(ledger): 修复导入批次回滚状态
feat(docs): 整理正式文档结构
```

每轮交付必须说明：

```text
改了哪个平台：服务端 / Flutter 客户端 / 手机端 / Web / 桌面端 / 文档
做了什么
如何检查
当前分支结构
可选手动验证命令
```
