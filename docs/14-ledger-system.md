# 14. 记账系统

## 1. 定位

记账系统用于记录个人消费与收入。MVP 目标是快速记录和统计，不追求完整专业复式记账。

## 2. MVP 能力

- 手动记账；
- 自然语言记账；
- 通用 CSV 导入；
- 支付宝账单 CSV 导入；
- 微信账单 CSV 导入；
- 导入预览；
- 批次回滚；
- 重复检测；
- 基础分类统计；
- 按时间查询；
- 按商户查询。

## 3. 交易字段

```text
amount
currency
direction
account_id
category_id
merchant
note
occurred_at
source
confidence
status
```

## 4. 账户模型

MVP 只做简化账户：

```text
微信
支付宝
现金
银行卡
其他
```

不做复杂账户余额校验。

## 5. 分类模型

默认分类：

```text
餐饮
交通
购物
学习
科研
娱乐
生活
医疗
住房
人情
其他
未分类
```

分类支持用户编辑。

## 6. 自然语言记账

示例：

```text
奶茶 12
```

解析：

```json
{
  "amount": 12,
  "direction": "expense",
  "category_hint": "餐饮",
  "merchant": "奶茶",
  "occurred_at": "now"
}
```

## 7. CSV 导入

CSV 导入必须经过 import_batches 和 import_rows，不允许直接写正式账单。

流程：

```text
上传 → 解析 → 预览 → 去重 → 分类 → 用户确认 → 入账
```

## 8. 去重策略

去重依据：

- 时间；
- 金额；
- 商户；
- source_provider；
- external transaction id；
- 文件 hash + row index。

重复项默认 skipped，用户可手动覆盖。

## 9. 批次回滚

导入批次 commit 后，如果用户回滚：

- 批次状态改为 rolled_back；
- 对应交易进入 user_trashed；
- 写 audit log；
- 不直接物理删除。

## 10. AI 分类

分类流程：

1. 规则优先；
2. 商户关键词匹配；
3. 历史用户习惯；
4. AI 分类；
5. 低置信度进入未分类。

## 11. 暂不做功能

MVP 不做：

- 信用卡账单周期；
- 报销；
- 分摊；
- 投资；
- 资产负债表；
- 自动通知监听；
- 银行 API；
- 支付宝/微信官方实时 API。
