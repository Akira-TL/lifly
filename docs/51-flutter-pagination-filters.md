# 51. Flutter 分页加载与基础筛选

## 背景

在 `50. Flutter 详情页与编辑删除地基` 之后，备忘、记账、任务列表已经具备真实 API、详情页、编辑/删除入口，但列表仍是一次性读取固定数量数据。

本切片补齐列表分页与基础筛选能力，继续保持“功能地基优先”，不做 UI 美化。

## 新增分页模型

新增：

```text
apps/client_flutter/lib/data/repositories/paged_result.dart
```

提供：

```text
PagedResult<T>
items
total
limit
offset
nextOffset
hasMore
fromData(...)
```

用于统一解析后端列表响应中的分页元数据。

## Repository 变更

以下仓库新增 `listPage(...)`：

```text
apps/client_flutter/lib/data/repositories/memo_repository.dart
apps/client_flutter/lib/data/repositories/ledger_repository.dart
apps/client_flutter/lib/data/repositories/task_repository.dart
```

同时保留旧 `list(...)`，避免破坏现有调用。

## 页面变更

### 备忘录

文件：

```text
apps/client_flutter/lib/features/memo/pages/memo_list_page.dart
```

新增：

```text
类型筛选：全部 / 备忘 / 日记 / 剪藏 / 文档
关键词搜索：q
第一页刷新
滚动接近底部自动加载更多
底部“加载更多”按钮
```

对应参数：

```text
type
q
limit
offset
```

### 记账

文件：

```text
apps/client_flutter/lib/features/ledger/pages/ledger_list_page.dart
```

新增：

```text
方向筛选：全部 / 支出 / 收入
第一页刷新
滚动接近底部自动加载更多
底部“加载更多”按钮
```

对应参数：

```text
direction
limit
offset
```

### 任务

文件：

```text
apps/client_flutter/lib/features/task/pages/task_list_page.dart
```

新增：

```text
状态筛选：全部 / 待办 / 进行中 / 已完成
第一页刷新
滚动接近底部自动加载更多
底部“加载更多”按钮
```

对应参数：

```text
task_status
limit
offset
```

## 测试

新增：

```text
apps/client_flutter/test/paged_result_test.dart
```

覆盖：

```text
分页元数据解析
nextOffset
hasMore
最后一页判断
```

原 widget test 继续覆盖核心页面与详情页基本链路。

## 验证

```bash
cd apps/client_flutter
flutter analyze .
flutter test
```

后端主链路回归：

```bash
bash scripts/smoke-mcp-v0.1.sh
```

## 后续

下一步建议进入 Local MCP / 本地客户端能力之前，可以先补一层通用列表状态组件：

```text
PagedListController / PagedListState
统一 PaginationFooter
统一 FilterChipOption
```

当前切片为了降低风险，先在三个页面局部实现分页状态，等行为稳定后再抽象。
