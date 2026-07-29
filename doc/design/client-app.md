# Flutter 客户端设计

## 1. 平台

当前产品基线：

- Windows；
- Android。

当前完整 UI/UX 与启动验证平台：

- Web。

共享 Flutter 主题 Runtime 与平台 Profile 已覆盖 Web、手机端和桌面端语义。macOS、iOS、Linux 仍需在对应真实构建环境完成发布验证，不能仅凭共享代码视为正式支持。

## 2. 客户端职责

客户端负责：

- 手动记录；
- 本地离线读写；
- 本地缓存；
- Markdown 编辑；
- 附件选择、上传、缓存；
- 同步状态展示；
- AI/MCP 调用入口；
- 数据查看、编辑、恢复、导出；
- 本地 read model 计算，包括首页概览、预算进度、分类占比、最近混合内容流、任务预警分组和标签统计；
- 跨端 Theme Runtime、主题包解析、设备偏好、平台 Profile、主题降级和 Core-first 启动。

客户端不负责：

- 云端 AI 推理；
- 云端 MCP tool handler；
- 对象存储权限决策；
- 账单 CSV 大规模解析；
- 多用户协作；
- 在页面层写死预算、分类占比、消费洞察、AI 分类状态、任务预警策略等长期产品规则。

客户端可以做展示格式化和兼容降级。正常联网状态下，正式产品语义优先来自云端拉取和同步后的同构数据；云端失败、断网或弱网时，客户端必须能降级到 Local Core / PowerSync 本地 read model，不能写假数据。

## 3. 应用结构

```text
lib/
├─ app/
│  ├─ router/
│  ├─ startup/
│  ├─ theme/
│  └─ shell/
├─ features/
│  ├─ capture/
│  ├─ memo/
│  ├─ ledger/
│  ├─ task/
│  ├─ asset/
│  ├─ import/
│  ├─ settings/
│  └─ sync/
├─ data/
│  ├─ local/
│  ├─ powersync/
│  ├─ api/
│  └─ repositories/
├─ domain/
│  ├─ entities/
│  ├─ usecases/
│  └─ value_objects/
└─ shared/
   ├─ widgets/
   ├─ utils/
   └─ constants/
```

## 4. 页面结构

### 4.1 手机端主入口

手机端底部导航固定为：

```text
首页 / 备忘 / AI / 记账 / 任务
```

AI 是居中主按钮。搜索和设置不占手机端底部一级入口。

当前 Flutter `AppShell` 已按该结构落地：手机端使用五入口底栏，AI 为中间强化按钮；首页顶部提供全局搜索和设置入口；宽屏 Flutter 使用受控 `compact / balanced / dashboard` 布局策略。Web 可以展开侧栏，桌面端可以使用紧凑侧栏，手机端保持不低于 48px 的交互区域。

### 4.2 Web / 桌面宽屏 Shell

Web dashboard 使用可折叠的 248px 左侧栏，桌面 compact 使用紧凑侧栏。两者共享首页、备忘、AI、记账、任务五个核心入口，不把手机底栏直接放大。

宽屏全局能力：

```text
搜索：侧栏入口或 Ctrl+K
快速记录：侧栏入口或 Ctrl+N
管理中心：账单导入、导入批次、数据导出、附件库、设置与诊断
```

管理中心只组织导航，不读取 Repository、API、Local Core 或 PowerSync 状态。具体业务状态继续由目标页面负责。

侧栏折叠状态和当前核心入口保存在设备本地。浏览器刷新或 `AppShell` 重建后恢复；非法入口索引被忽略并回到首页。管理页返回和主题切换不得重建当前核心页、API Client 或其他业务服务。

全局快捷键只在没有文本输入焦点时生效。`TextField`、`TextFormField` 或底层 `EditableText` 获得焦点后，Shell 必须让出 `Ctrl+K` 和 `Ctrl+N`。

### 4.3 共享页面状态

客户端统一使用主题感知的共享页面状态：

```text
Loading：可读进度说明和 live region
Empty：说明原因，可选主操作
Error：错误原因和重试操作
Offline：说明已有本地能力与需要联网的边界
```

共享页面状态不依赖具体 Repository。手机端保持可滚动和下拉刷新，Web / 桌面端把说明内容限制在可读宽度。附件库已作为首个真实消费页面，备忘、记账和任务继续复用同一 `AsyncContentScaffold`。

### 4.4 页面集合

客户端长期页面集合：

- 首页 / 今日关注；
- AI Capture / 快速记录；
- 备忘录列表；
- 备忘录编辑；
- 记账列表；
- 新建账单；
- 预算与统计；
- 导入账单；
- 任务列表；
- 新建任务；
- 附件管理；
- 回收站；
- 搜索；
- 设置；
- 同步状态；
- API / Local Core / PowerSync 诊断。

## 5. 快速记录

快速记录页应支持：

- 一句话输入；
- 选择手动解析或 AI 解析；
- 本地离线时保存为普通 capture；
- 在线时可调用云端 MCP / AI 做解析增强；
- Capture session、历史 turns、解析预览、提交结果、附件上下文和撤销链路必须能本地持久化；
- AI 已设置的备忘、任务或账单必须在会话中展示实体结果，并提供修改、撤销和继续对话入口；
- 手机端使用历史会话面板，宽屏使用会话侧栏，不把手机布局原样放大；
- 附件展示真实解析状态，未接入 PDF/OCR/STT 时不得伪装已识别；
- 提交或关闭会话。

## 6. Markdown 编辑器

MVP 采用 Markdown 编辑器 + 附件卡片，不做块编辑器。

支持：

- Markdown 输入；
- 图片插入；
- 文件卡片；
- 外部链接；
- asset:// 引用；
- 预览模式。

## 7. 附件上传与缓存

附件库上传使用统一链路：

```text
用户选择真实文件
  ↓
create-upload-url 创建 Asset 与上传意图
  ↓
客户端向对象存储 presigned URL 执行 PUT
  ↓
upload-complete 校验对象并把 sync_status 更新为 synced
```

客户端不得使用固定占位文件名模拟上传。文件类型根据扩展名映射为 image / pdf / audio / file，并携带可识别的 MIME；上传失败只提示错误，不把未完成资产伪装成已同步。

本地缓存策略：

- 最近使用附件自动缓存；
- 图片缩略图缓存；
- 用户可清理缓存；
- 缓存丢失不影响云端数据；
- 上传失败可重试。

## 8. 同步状态 UI

必须展示：

- 当前在线/离线；
- 最近同步时间；
- 是否有待同步项目；
- 附件上传状态；
- 同步错误提示。

## 9. 离线策略

无网时：

- 可以手动创建备忘；
- 可以手动记账；
- 可以手动创建任务；
- 可以编辑已缓存内容；
- 不保证 AI 可用；
- 不保证新附件上传；
- 可将附件标记为待上传。

## 10. 性能要求

基础要求：

- Lifly Core 不依赖网络、自定义字体、大型装饰资源或主题授权；
- Web 先显示内联 HTML 启动壳，再显示 Flutter Core Shell；
- 设备主题偏好和缓存主题只能在 Core 首帧后恢复；
- 首页查询走本地 SQLite；
- 大列表分页；
- Markdown 预览懒加载；
- 图片缩略图优先；
- 附件不自动全量下载。

当前 Web 初始产物预算：

```text
Default main.dart.js        <= 8 MiB
Application main.dart.wasm  <= 8 MiB
CanvasKit renderer Wasm     <= 10 MiB
index.html / bootstrap      <= 32 KiB each
```

默认 Web 和 Wasm 构建都必须通过 `scripts/check-web-theme-performance.sh`，生产渲染器选择继续以真实设备、网络和兼容性测量为准。

## 11. 主题应用框架

客户端主题入口统一为 Theme Runtime：

```text
Lifly Core 同步可用
  ↓
设备偏好恢复
  ↓
已安装主题包解析
  ↓
平台 Profile 与色彩模式解析
  ↓
不可变 Theme Snapshot
```

业务页面不得解析 Manifest、验证签名或自行维护主题家族分支。业务组件通过 Flutter Theme 和语义 Token 获取样式。

主题切换不得重建 API Client、PowerSync、Local Core、AI 服务或当前路由。主题故障必须保留当前业务功能并最终回退 `Lifly Core`。

完整协议和安全边界见 `doc/architecture/theme-application-framework.md`。

## 12. Web Core-first 启动

Web 启动记录以下里程碑：

```text
lifly-host-feedback
lifly-entrypoint-loaded
lifly-engine-initialized
lifly-dart-entrypoint
lifly-flutter-first-frame
lifly-core-usable
lifly-theme-activated
```

HTML 启动壳不加载远程字体和插图。Flutter 首帧后才读取 SharedPreferences、打开主题缓存并验证可选主题。主题恢复失败只记录诊断，不显示阻塞启动弹窗。
