# 49. Flutter shared async UI 地基

## 背景

在 `48. Flutter 首页/备忘/记账/任务真实 API 地基` 中，备忘录、记账、任务页面已经接入真实 API，但每个页面都重复维护了以下状态 UI：

```text
loading
error
empty
refresh
```

本切片先抽通用组件，降低后续继续做详情页、编辑/删除、分页加载时的重复成本。

## 新增组件

新增文件：

```text
apps/client_flutter/lib/shared/widgets/async_content.dart
```

包含：

```text
AsyncContentScaffold
EmptyState
ErrorState
```

### AsyncContentScaffold

负责统一处理：

```text
isLoading=true  -> CircularProgressIndicator
error != null   -> ErrorState
isEmpty=true    -> RefreshIndicator + EmptyState
正常数据        -> RefreshIndicator + child
```

调用方只需要传入：

```text
isLoading
error
isEmpty
onRefresh
emptyIcon
emptyTitle
emptySubtitle
child
```

### EmptyState

统一空态样式：

```text
图标
标题
说明文字
AlwaysScrollableScrollPhysics
```

空态仍支持下拉刷新。

### ErrorState

统一错误态样式：

```text
错误图标
错误文本
重试按钮
```

## 已迁移页面

```text
apps/client_flutter/lib/features/memo/pages/memo_list_page.dart
apps/client_flutter/lib/features/ledger/pages/ledger_list_page.dart
apps/client_flutter/lib/features/task/pages/task_list_page.dart
```

这些页面仍保持原有真实 API 路径和最小创建动作不变。

## 暂未迁移页面

首页暂时保留独立实现，因为它不是纯列表页，包含多块 dashboard 卡片、趋势图和最近交易。后续可以在进一步抽象 dashboard 组件后再迁移局部错误态。

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

下一步可以在共享 async UI 的基础上继续：

```text
1. 详情页基础路由与页面骨架
2. 编辑/删除动作
3. 分页加载更多
4. 通用表单 dialog/component
```
