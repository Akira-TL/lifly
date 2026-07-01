# 48. Flutter 首页/备忘/记账/任务真实 API 地基

## 背景

本切片承接 `47. Flutter API health + MCP smoke 接入`，目标是让 Flutter 客户端的核心页面从占位 UI 进入真实 API 可用状态。

本切片不处理完整交互体验，不做复杂筛选、分页、编辑、删除、离线同步或 PowerSync，只先打好真实 API 接入地基。

## 范围

完成页面：

```text
首页
备忘录
记账
任务
```

## 首页

首页继续使用：

```http
GET /api/v1/dashboard
```

本次修正了前后端字段不一致问题。后端当前返回：

```text
month_income
month_expense
daily_trend
recent_transactions
memo_total
task_todo
task_total
```

Flutter 首页现在兼容读取：

```text
month_income / monthly_income
month_expense / monthly_expense
daily_trend / weekly_trend
```

并新增：

```text
备忘数量
待办数量
任务总数
```

## 备忘录页

页面从占位文字改为真实 API：

```http
GET  /api/v1/memos
POST /api/v1/memos
```

实现：

```text
列表加载
下拉刷新
空态
错误态
最小新建备忘 dialog
```

## 记账页

页面从占位文字改为真实 API：

```http
GET  /api/v1/ledger/transactions
GET  /api/v1/ledger/summary
POST /api/v1/ledger/transactions
```

实现：

```text
交易列表加载
收支 summary
下拉刷新
空态
错误态
最小记一笔 dialog
```

## 任务页

页面从占位文字改为真实 API：

```http
GET  /api/v1/tasks
POST /api/v1/tasks
POST /api/v1/tasks/{task_id}/complete
```

实现：

```text
任务列表加载
下拉刷新
空态
错误态
最小新建任务 dialog
checkbox 完成任务
```

## 测试策略

Flutter widget test 不访问真实网络，使用 `FakeApiClient` 注入以下响应：

```text
/dashboard
/memos
/ledger/transactions
/ledger/summary
/tasks
```

测试覆盖 AppShell 中：

```text
首页启动
切换备忘页并看到真实 API 形态数据
切换记账页并看到真实 API 形态数据
切换任务页并看到真实 API 形态数据
```

## 验证

```bash
cd apps/client_flutter
flutter analyze
flutter test
```

后端主链路回归：

```bash
bash scripts/smoke-mcp-v0.1.sh
```

本切片提交前全部通过。

## 后续待做

```text
1. 抽取通用 AsyncListScaffold / EmptyState / ErrorState 组件
2. 备忘录编辑/删除/详情页
3. 记账筛选、分类、日期选择、编辑/删除
4. 任务筛选、编辑、取消完成、due/remind 时间选择
5. 分页加载更多
6. 与 PowerSync/离线同步层对接
```
