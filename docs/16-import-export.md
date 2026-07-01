# 16. 导入导出设计

## 1. 目标

Lifly 必须尊重用户数据所有权。所有核心数据都应该能导入、导出、迁移。

## 2. 导入范围

MVP 支持：

- 通用账单 CSV；
- 支付宝账单 CSV；
- 微信支付账单 CSV；
- Markdown 备忘录导入，预留；
- ICS 日历导入，预留。

## 3. 导出范围

MVP 支持或预留：

- 账单 CSV；
- 备忘录 Markdown；
- 任务 CSV/JSON；
- 全量 JSON；
- 附件打包。

## 4. CSV 导入流程

```text
用户上传 CSV
    ↓
创建 import_batch
    ↓
解析 import_rows
    ↓
字段映射
    ↓
去重检测
    ↓
分类建议
    ↓
预览
    ↓
用户确认
    ↓
commit
    ↓
写入 ledger_transactions
    ↓
写 audit_logs
```

## 5. 导入状态

import_batch.status：

```text
preview
committed
rolled_back
failed
```

import_row.status：

```text
pending
imported
skipped
duplicate
error
```

## 6. 通用 CSV 模板

建议字段：

```csv
occurred_at,direction,amount,currency,category,merchant,account,note
2026-06-21 12:00,expense,18,CNY,餐饮,食堂,微信,午饭
```

## 7. 支付宝/微信账单

需要单独做 parser。不同版本账单格式可能变化，parser 必须支持：

- 编码识别；
- 列名映射；
- 金额清洗；
- 收入/支出识别；
- 商户识别；
- 退款识别，MVP 可标记；
- 重复检测。

## 8. 导入预览

预览页必须展示：

- 总行数；
- 有效行数；
- 重复行数；
- 错误行数；
- 分类分布；
- 总收入/支出；
- 可编辑行。

## 9. 批次回滚

回滚时：

- 对批次创建的交易进入 user_trashed；
- import_batch 状态为 rolled_back；
- 写 audit log；
- 保留 import_rows 记录。

## 10. 导出

导出必须异步处理，特别是附件打包。

导出任务状态：

```text
pending
processing
ready
failed
expired
```

导出文件应设置有效期，避免长期占用存储。
