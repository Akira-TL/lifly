# 跨端主题应用框架

## 1. 目标

Lifly 的主题能力不是两套固定皮肤，而是一个面向 Web、手机端和桌面端的可扩展主题应用框架。

框架目标：

```text
Lifly Core 极致轻量并始终可用
多主题共享同一业务功能和数据契约
复杂主题可以按需加载，不拖慢 Core 首帧
主题可以版本化安装、缓存、授权、回滚和降级
未来可接入主题商店、付费授权和推荐机制
远程主题只能提供声明式数据与资源，不能执行任意代码
```

## 2. 核心领域模型

### 2.1 Theme Family

Theme Family 表示一套完整设计语言，与浅色或深色模式相互独立。

例如：

```text
Lifly Core
温和生活
高效专注
纸张手账
像素生活
```

### 2.2 Color Mode

Color Mode 表示主题家族内部的色彩模式：

```text
system
light
dark
oled
highContrast
```

主题家族声明支持的模式。用户可以保留预期模式；当前主题不支持时，运行时按确定规则降级，不修改业务功能。

### 2.3 Theme Package

Theme Package 是可安装、缓存和升级的版本化分发单元，由以下内容组成：

```text
Theme Manifest
Semantic Theme Tokens
可选资源
平台覆盖
完整性与签名元数据
```

主题包不能包含远程 Dart、脚本、表达式、API 路径、数据库查询或业务行为。

### 2.4 Theme Snapshot

Theme Runtime 将主题包、平台、色彩模式和降级结果解析为不可变 Theme Snapshot。

Snapshot 至少包含：

```text
主题身份与版本
性能等级
实际色彩模式
平台 Profile
语义 Tokens
Light / Dark ThemeData
Material ThemeMode
```

业务组件只消费当前 Snapshot，不直接解析主题包。

## 3. Lifly Core

`Lifly Core` 是内置、免费、不可卸载的最终兜底主题。

硬性约束：

```text
不依赖网络
不依赖授权服务
不依赖远程主题目录
不依赖自定义字体
不依赖大型插图或装饰资源
不依赖复杂持续动画
不等待 PowerSync 或 API
```

应用启动时先同步生成 Core Snapshot。偏好、缓存主题、授权和主题资源只允许在 Core 首帧之后恢复。

## 4. 声明式主题协议

### 4.1 Manifest

Manifest 描述：

```text
theme_id
version
display_name
description
author
minimum_app_version
supported_platforms
supported_color_modes
performance_class
assets
fallback_theme_id
entitlement_type
platform_overrides
integrity
```

主题 ID 使用稳定的小写命名空间标识。版本使用语义化版本。

### 4.2 Semantic Tokens

业务组件消费语义，而不是主题特定常量。

当前 Token 组：

```text
colors
  primary / onPrimary / secondary / surface / onSurface
  critical / warning / success / info / neutral

typography
  fontFamily / titleScale / bodyScale / labelScale

spacing
  page / card / inline

radius
  card / control

elevation
  card

density
  visual

motion
  enabled / fast / normal
```

Core 为每个必需语义提供默认值。主题可以覆盖允许的值，但不能删除 critical、warning 等产品状态语义。

未知必需字段拒绝主题包；未知可选 Token 可以忽略，以支持协议向前兼容。

### 4.3 Assets

资源必须声明：

```text
id
相对路径
资源类型
是否必需
最大字节数
SHA-256
```

禁止绝对路径、路径穿越、URL scheme、未声明资源和超限资源。

缺失必需资源会拒绝安装；缺失可选资源使用轻量降级，不阻塞 Core 或主题基础样式。

## 5. Theme Runtime

Theme Runtime 是应用唯一主题状态入口，负责：

```text
同步提供 Lifly Core
枚举已安装主题
恢复设备偏好
选择主题家族
选择色彩模式
解析平台覆盖
发布当前不可变 Snapshot
记录恢复失败原因
```

主题切换只通知主题消费层，不重建 API Client、PowerSync、Local Core、AI 服务或当前路由。

## 6. 偏好与多设备边界

当前设备本地保存：

```text
主题家族
色彩模式
```

长期模型：

```text
账户级默认主题
  +
设备级主题覆盖
  +
设备本地色彩模式
```

设备覆盖优先于账户默认。账户同步属于后续服务端能力，不阻塞本地主题框架。

## 7. 安装、缓存与回滚

安装顺序固定为：

```text
解析声明协议
  ↓
验证摘要、资源和签名
  ↓
验证应用版本与平台
  ↓
验证授权
  ↓
写入新版本槽位
  ↓
原子移动 active 指针
```

失败更新不能替换当前已知可用版本。

解析顺序：

```text
当前 active 版本
  ↓ 不可用
其他已缓存已知可用版本
  ↓ 不可用
Manifest 声明 fallback
  ↓ 不可用
Lifly Core
```

原生/桌面端使用应用支持目录中的版本槽位和可恢复 active 指针；Web 使用版本化键值缓存。两者实现同一 Theme Package Cache 接口。

## 8. 签名与信任边界

主题包是内容，不是插件。

安全原则：

```text
远程主题不执行 Dart 或脚本
主题数据不能提供业务文案、无障碍标签、API 路径或查询
官方主题必须经过摘要、资源和签名验证
没有配置生产公钥或正式验证器时默认拒绝远程主题
测试环境可以显式注入本地确定性验证器
```

未来插件系统必须单独进行架构和安全评审，不能借用主题包绕过代码审核。

## 9. 授权与商业化边界

Entitlement 与渲染分离。运行时只消费“是否允许使用”的授权结果，不知道授权来自：

```text
免费
单次购买
订阅
活动兑换
赠送
```

已下载的付费主题可以在有效离线授权允许时继续使用。商业宽限期、支付、恢复购买和服务端授权 API 属于后续商业化阶段。

主题推荐同样独立：推荐只调整展示和排序，不自动替用户切换主题。

## 10. 平台覆盖与受控布局

共享主题允许声明 Web、手机、桌面 Profile：

```text
layoutVariant
visualDensityAdjustment
minimumInteractiveDimension
focusRingWidth
hoverEnabled
keyboardNavigation
```

布局只允许：

```text
compact
balanced
dashboard
```

主题可以调整密度、侧栏展开方式和批准的响应式组合，但不能：

```text
隐藏核心业务模块
删除紧急或风险状态
改变权限和业务规则
替换产品页面实现
重排安全关键操作
```

手机端最小交互区域不能低于 48px。系统减少动态效果设置优先于主题动效。

## 11. Core-first Web 启动

Web 启动阶段：

```text
HTML 内联启动壳立即反馈
  ↓
Flutter entrypoint
  ↓
Flutter engine
  ↓
Lifly Core 首帧与可操作 Shell
  ↓
设备偏好恢复
  ↓
本地缓存主题验证与激活
```

启动里程碑：

```text
lifly-host-feedback
lifly-entrypoint-loaded
lifly-engine-initialized
lifly-dart-entrypoint
lifly-flutter-first-frame
lifly-core-usable
lifly-theme-activated
```

浏览器可以通过 Performance Marks 读取实际时间。无浏览器环境下，CI 使用启动契约、产物体积和 Release 双构建作为回归门禁。

## 12. 性能等级

```text
core
  无外部主题依赖，首帧基线

standard
  少量可缓存资源，Core 后加载

rich
  字体、插图、动画等增强资源，允许更慢的首次加载
```

复杂主题的性能不能用于放宽 Core 门禁。

当前初始产物预算：

```text
Default main.dart.js        <= 8 MiB
Application main.dart.wasm  <= 8 MiB
CanvasKit renderer Wasm     <= 10 MiB
HTML / bootstrap            <= 32 KiB each
```

预算由 `scripts/check-web-theme-performance.sh` 固化，后续应根据真实设备和网络测量逐步收紧。

## 13. 当前边界

v0.8.0 已完成：

```text
跨端 Theme Runtime
Lifly Core
声明式 Manifest / Tokens
测试主题
设备偏好
平台 Profile 与受控布局
版本缓存、授权占位、完整性与回滚
Web Core-first 启动
默认 Web / Wasm 构建门禁
```

尚未包含：

```text
正式主题商店
支付和订阅
生产主题授权服务
生产签名公钥配置
第三方主题投稿与审核
主题推荐算法
完整商业主题家族
任意远程插件代码
```
