# Local Core 持久化回归验证

## 版本

```text
0.2.7
```

## 验证目标

确认 Local Core 不只是“能写一次”，而是在数据库关闭并重新打开后仍然保留数据、状态、revision 和 audit_logs。

## 覆盖范围

```text
memo create/update/delete 后重启验证
task create/update/complete/delete 后重启验证
expense create/search/summary/delete 后重启验证
soft delete 状态保留
revision 保留
audit_logs 保留
```

## 测试文件

```text
apps/client_flutter/test/support/powersync_persistence_harness.dart
apps/client_flutter/test/memo_persistence_regression_test.dart
apps/client_flutter/test/task_persistence_regression_test.dart
apps/client_flutter/test/ledger_persistence_regression_test.dart
```

## 执行命令

```bash
cd apps/client_flutter
flutter test test/memo_persistence_regression_test.dart
flutter test test/task_persistence_regression_test.dart
flutter test test/ledger_persistence_regression_test.dart
```

完整回归：

```bash
bash scripts/check-client-flutter.sh
```

## 环境说明

PowerSync 原生库不可用时，测试辅助工具会安全跳过当前持久化测试，不把环境缺失误判为业务失败。原生库可用时，会使用临时数据库路径执行真实关闭/重开验证。

## 当前边界

```text
不验证 Cloud Sync
不验证 PowerSync uploadData
不验证跨设备同步
不验证账号切换后的数据隔离
```
