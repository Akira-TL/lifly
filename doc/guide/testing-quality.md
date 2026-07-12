# 测试与质量保障

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
scripts/check-api.sh
scripts/check-client-flutter.sh
scripts/check-powersync-sync-scope.sh
scripts/check-v0.7-release-gate.sh
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
Reminder 状态只使用 pending / delivered / failed / cancelled
到期认领必须生成 dispatch token 和短期 lease，重复认领继续使用 reminder ID 作为平台幂等键
送达和失败回写必须校验当前 dispatch token，陈旧 token 不得覆盖新状态
失败提醒必须覆盖指数退避、最大尝试次数和手动 retry
任务完成、取消、删除和策略 dismiss 必须取消未送达提醒
平台通知必须通过 ReminderNotificationAdapter 接入，业务层不得直接依赖单一通知插件
Local Core 可在断网状态计算首页 overview、预算统计、分类占比、任务预警和标签统计
LedgerRepository 覆盖预算云端优先读取和失败后本地 fallback
预算创建 / 更新 / 删除必须覆盖总预算与分类预算
同一用户、月份和分类范围不得存在重复 active 预算
分类预算只能绑定 active 的 expense 分类
预算金额、阈值、月份格式必须通过 API 与 Local Core 双侧校验
预算写入必须生成 ledger_budget 审计快照并递增 revision
PowerSync 必须能上传 ledger_budget，服务端拒绝陈旧 revision 与重复预算
云端预算写入结果不确定时不得自动再写本地，避免双写
本地 read model 与云端 API 字段同构
首页 sync_summary 必须来自 PowerSync currentStatus 或服务端可验证的配置与同步统计
首页 import_summary 必须来自最新 import_batches，不得固定返回 idle
首页 settings_summary 不得暴露数据库连接串、JWT、对象存储密钥等敏感配置
PowerSync 部署配置必须通过 scripts/check-powersync-sync-scope.sh，至少覆盖 infra/powersync-required-tables.txt
PowerSync CRUD mapper 和服务端 sync push 必须覆盖 reminder revision 与派发状态字段
repository 读取支持 cloudPreferred，云端失败或断网时才降级 Local Core
开发期 Local Core 默认 user_id 必须与 PowerSync 凭据的 local-dev 对齐
断网手动验收首页、记账统计、任务预警、备忘分类状态
API / repository / UI 的字段边界清楚
AI Capture 本地模式必须覆盖 mcp_capture_sessions、mcp_capture_turns、mcp_undo_actions、source_capture_id、ai_trashed undo 链路
AI Capture 连续会话必须覆盖 session 列表/恢复、append turn、逐 turn commit、result_entities、undo_token、dismiss
AI Capture 修改链必须保留 supersedes_turn_id；已 committed / partial 的 turn 必须先 undo 才允许 revise
PowerSync capture PATCH 不得清空未携带的 text / actions / asset_ids / asset_context / result_entities / undo_token
AI Capture 附件上下文必须区分 ready / metadata_only / pending_upload / unsupported / missing / inactive / failed，未接入 PDF/OCR/STT/外链抓取时不得伪装已解析
服务端文本附件提取必须限制单文件字节数、单文件文本长度和单次会话合计文本长度，并覆盖编码、超限与存储错误
Flutter AI 会话消费测试必须覆盖历史入口、连续输入、已设置结果、修改、撤销和附件能力提示
附件库上传必须覆盖真实文件选择、create-upload-url、对象存储 PUT 与 upload-complete，禁止占位文件名直接注册
产品地基发布门禁必须检查 Dart/Python 业务文件不超过 800 行，并拒绝首页固定状态占位值和附件占位上传入口
AI Capture 本地规则拆分必须覆盖 task_create / expense_create / memo_create 候选动作
```
