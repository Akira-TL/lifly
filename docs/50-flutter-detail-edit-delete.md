# 50. Flutter 详情页与编辑删除地基

## 背景

在核心页面已经接入真实 API 后，本切片继续补齐详情页与基础编辑/删除入口。

本切片仍不做 UI 美化，只保证页面链路、接口调用、语法和测试正确。

## 新增详情页

```text
apps/client_flutter/lib/features/memo/pages/memo_detail_page.dart
apps/client_flutter/lib/features/ledger/pages/ledger_detail_page.dart
apps/client_flutter/lib/features/task/pages/task_detail_page.dart
```

## 列表到详情

以下列表页已支持点击条目进入详情：

```text
备忘录列表 -> 备忘详情
记账列表   -> 账单详情
任务列表   -> 任务详情
```

详情页返回后，列表会重新拉取数据，确保详情中编辑或删除后的列表状态能刷新。

## Repository 补齐

记账仓库新增：

```text
get(id)
update(id, data)
delete(id)
```

任务仓库新增：

```text
get(id)
update(id, data)
```

备忘仓库原本已具备 get/update/delete，本切片直接复用。

## 详情页能力

### 备忘详情

```text
GET    /api/v1/memos/{memo_id}
PUT    /api/v1/memos/{memo_id}
DELETE /api/v1/memos/{memo_id}
```

支持查看、编辑标题/内容/标签/心情、删除。

### 账单详情

```text
GET    /api/v1/ledger/transactions/{tx_id}
PUT    /api/v1/ledger/transactions/{tx_id}
DELETE /api/v1/ledger/transactions/{tx_id}
```

支持查看、编辑方向/金额/商户/备注、删除。

### 任务详情

```text
GET    /api/v1/tasks/{task_id}
PUT    /api/v1/tasks/{task_id}
POST   /api/v1/tasks/{task_id}/complete
DELETE /api/v1/tasks/{task_id}
```

支持查看、编辑标题/描述/优先级/状态、完成任务、删除。

## Flutter Hero 修复

由于 AppShell 当前使用多页面保活结构，多个页面的 FloatingActionButton 会同时存在。默认 FAB heroTag 会在进入详情页时冲突，因此本切片为以下 FAB 设置了唯一 heroTag：

```text
memo-create-fab
ledger-create-fab
task-create-fab
asset-create-fab
```

这是代码正确性修复，不属于 UI 美化。

## 测试

Widget test 已扩展覆盖：

```text
首页启动
进入备忘列表
进入备忘详情
进入记账列表
进入账单详情
进入任务列表
进入任务详情
```

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
