# 计划文档

本目录只存放临时执行计划，不作为长期正式文档入口。

## 使用规则

计划文档用于承接尚未实现、需要跨平台拆分的开发内容。涉及手机端核心体验、统计、首页、任务预警和分类能力时，默认采用本地优先：先规划 Local Core / PowerSync 本地计算，再规划云端同构兜底。计划完成后必须执行回写和清理：

```text
计划确认
  ↓
按计划开发
  ↓
代码和测试通过
  ↓
把已经落地的长期结论回写到固定正式文档
  ↓
删除对应 plan 文档
```

固定文档归档位置：

```text
产品需求 -> doc/requirements/
API 契约 -> doc/api/
数据模型和架构 -> doc/architecture/
客户端和交互设计 -> doc/design/
开发、测试、状态、路线 -> doc/guide/
法律、安全、隐私 -> doc/legal/
历史材料 -> doc/archive/
```

## 禁止事项

```text
不把 plan 当长期文档入口
不在 plan 里替代 API 契约
不在 plan 里替代数据模型文档
不在 plan 完成后保留重复内容
不继续使用数字前缀命名计划
```

## 最近收口

`mobile-product-foundation.md` 对应的 v0.7.0 产品地基计划已经完成并回写到 API、架构、客户端、测试和当前状态文档，发布门禁由 `scripts/check-v0.7-release-gate.sh` 长期维护，因此计划文件已删除。

`theme-application-framework.md` 对应的 v0.8.0 跨端主题应用框架已经完成并回写到主题架构、Flutter 客户端、UI 信息架构、测试、路线图和当前状态文档，发布门禁由 `scripts/check-v0.8-release-gate.sh` 长期维护，因此计划文件已删除。

`web-shell-navigation.md` 对应的 v0.8.1 Web 极简 Shell 与全局导航已经完成并回写到 Flutter 客户端、UI 信息架构、测试、路线图、任务池和当前状态文档，发布门禁由 `scripts/check-v0.8.1-release-gate.sh` 长期维护，因此计划文件已删除。

`web-home-workbench.md` 对应的 v0.8.2 Web 首页已按 A 方向“今日处理队列”原型重构侧栏、顶栏、主工作区和日程右栏，并完成代码、测试和构建检查。长期结论已回写到客户端设计、UI 信息架构、路线图、任务池和当前状态文档，因此计划文件已删除；浏览器视觉验收在版本收口前完成。
