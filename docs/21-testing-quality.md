# 21. 测试与质量保障

## 1. 测试目标

Lifly 需要重点保证：

- 数据不丢；
- 同步可靠；
- AI 写入可追踪；
- 删除可恢复；
- CSV 导入可回滚；
- 附件不破坏正文；
- MCP 工具行为稳定。

## 2. 测试类型

```text
unit tests
integration tests
contract tests
e2e tests
sync tests
import tests
mcp tests
security tests
```

## 3. 单元测试

重点：

- 金额解析；
- 时间解析；
- 分类映射；
- 删除状态机；
- audit log 生成；
- CSV 行解析；
- 附件引用解析。

## 4. 集成测试

重点：

- API 创建 memo；
- API 创建 transaction；
- API 创建 task；
- 附件上传流程；
- import batch commit；
- import batch rollback；
- MCP capture_commit。

## 5. MCP Contract Test

每个 MCP tool 必须有 schema 测试。

测试：

- 参数合法；
- 参数非法；
- 权限错误；
- 写入成功；
- audit log 存在；
- undo 可用。

## 6. 同步测试

测试场景：

- 离线创建备忘，联网后同步；
- 离线创建账单，联网后同步；
- 两端同时修改同一任务；
- 删除后另一端同步；
- purged 后另一端不恢复旧内容；
- 附件 metadata 同步但二进制按需下载。

## 7. CSV 导入测试

测试：

- 通用 CSV；
- 支付宝 CSV；
- 微信 CSV；
- 编码异常；
- 空行；
- 重复行；
- 金额格式异常；
- 批次回滚。

## 8. 附件测试

测试：

- 图片上传；
- PDF 上传；
- 外链注册；
- 上传失败重试；
- 本地缓存清理；
- 删除 memo 后附件引用检查；
- 孤儿附件清理。

## 9. 安全测试

测试：

- 越权访问；
- 访问他人 asset；
- token 撤销；
- MCP token 失效；
- presigned URL 过期；
- 日志脱敏。

## 10. 发布前检查清单

发布前必须确认：

- 数据库迁移通过；
- 客户端可离线启动；
- 登录失效能重新登录；
- CSV 导入可回滚；
- AI 删除进入 AI 回收站；
- 用户删除进入普通回收站；
- 附件上传失败不导致 memo 丢失；
- 多端同步一致。

## 11. 当前常用检查入口

测试和检查入口以 `scripts/` 下脚本为准，不再用独立 release gate 文档记录流水。

常用入口：

```text
scripts/check-client-flutter.sh
scripts/check-v0.4-ai-write.sh
scripts/smoke-mcp-v0.1.sh
```

服务端、Flutter、MCP、导入导出和同步相关检查应该沉淀到脚本、CI 和本文件，而不是继续新增一次性的发布门禁文档。

## 12. 产品地基质量门槛

涉及首页、预算、分类、任务预警和 AI Capture 的版本，额外检查：

```text
客户端不伪造预算金额
客户端不伪造分类占比
客户端不伪造消费洞察
客户端不根据字符串猜测 AI 已分类状态
客户端不写死任务提前提醒策略
API / repository / UI 的字段边界清楚
```
