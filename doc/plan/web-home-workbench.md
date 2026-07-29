# v0.8.2 Web 首页清晰工作台

## 平台范围

本计划只修改 Flutter Web 首页与共享视觉基础。服务端、手机端和桌面端业务布局不在本轮改造范围；共享主题能力必须保持跨端兼容。

## 目标

把已确认的 A 方向“清晰工作台”落到真实 `HomeOverview` 数据页面：

- 异常与待处理事项优先于统计；
- 同类信息收进少量分组面板，不把每一条数据做成独立卡片；
- Web 宽屏使用主次两栏，窄屏自然降级为单栏；
- 颜色只表达 critical / warning / success / info 等语义，不使用装饰性渐变；
- 保留云端优先、本地兜底的数据链路，不引入页面假数据。

## 开发切片

1. 新增公开的主题语义色扩展，把主题包中的 critical、warning、success、info、neutral 注入 Flutter `ThemeData`。
2. 新增可复用的连续分组面板、区块标题和空行组件，作为后续备忘、记账、任务页面的共同视觉基础。
3. 重构首页：
   - 顶部真实数据来源与同步摘要；
   - 今日指标连续统计条；
   - 今日关注连续列表；
   - 月度收支、预算、分类占比和财务洞察；
   - 七日趋势；
   - 最近混合活动流。
4. 增加 Web 宽屏与窄屏 Widget 测试，验证真实字段消费、布局切换和主题语义色。
5. 通过 Flutter analyze、相关测试、完整测试和 Web 构建检查后，回写正式文档并删除本计划。

## 验收边界

```text
首页不硬编码 red / orange / green 等业务状态颜色
首页不创建每条数据一个 Card
Web >= 1080px 使用主次两栏
窄屏保持单列滚动和下拉刷新
attention_items、finance_overview、daily_trend、recent_activity、sync/import/settings summary 均有真实消费
页面源码单文件不超过 800 行
默认 Web 与 Wasm 构建预算不回退
```
