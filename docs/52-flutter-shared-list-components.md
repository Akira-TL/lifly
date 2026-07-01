# 52. Flutter 列表筛选与分页组件抽取

## 背景

在 `51. Flutter 分页加载与基础筛选` 中，备忘、记账、任务三个列表页都实现了分页加载和基础筛选，但每个页面都保留了相似的筛选 Chip 与分页底部组件。

本切片只做组件抽取，不改变 API、不改变页面功能、不做 UI 美化。

## 新增共享组件

### ListFilterBar

新增文件：

```text
apps/client_flutter/lib/shared/widgets/list_filter_bar.dart
```

包含：

```text
ListFilterOption
ListFilterBar
```

用途：

```text
横向筛选 Chip 列表
统一 selectedValue / onChanged / options 输入
支持 null value 表示“全部”
```

当前接入页面：

```text
备忘录：全部 / 备忘 / 日记 / 剪藏 / 文档
记账：全部 / 支出 / 收入
任务：全部 / 待办 / 进行中 / 已完成
```

### PaginationFooter

新增文件：

```text
apps/client_flutter/lib/shared/widgets/pagination_footer.dart
```

用途：

```text
显示加载中状态
显示“加载更多（current/total）”按钮
显示“已显示 current/total”终态
```

## 页面变更

以下页面移除了各自私有的 `_FilterChipOption` / `_PaginationFooter`：

```text
apps/client_flutter/lib/features/memo/pages/memo_list_page.dart
apps/client_flutter/lib/features/ledger/pages/ledger_list_page.dart
apps/client_flutter/lib/features/task/pages/task_list_page.dart
```

保留页面自身状态逻辑：

```text
_scrollController
_hasMore
_isLoadingMore
_loadFirstPage
_loadMore
```

原因是分页状态后续可能继续与搜索、筛选、离线缓存、Local MCP 同步状态绑定。本切片先抽 UI 组件，不提前抽象复杂状态机。

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

后续如果三个页面分页状态继续稳定，可以再抽：

```text
PagedListController
PagedListState
PagedListView
```

但建议等 Local MCP / 离线同步需求明确后再抽状态机，避免过早抽象。
