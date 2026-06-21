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
