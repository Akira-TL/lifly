# v0.8.0 跨端主题应用框架规格

状态：已确认，待拆分工单。

GitHub Issue：#36 `[LC-0800] 跨端主题应用框架规格`

平台范围：共享 Flutter 客户端主题层，覆盖 Web、手机端和桌面端；首个完整验收平台为 Flutter Web。

## Problem Statement

Lifly 已完成备忘、记账、任务、AI Capture、本地优先、云端同步和导入导出等产品地基，但当前客户端主题能力仍只是固定的 Material 3 `ThemeData`。这种实现无法支撑长期的多主题体验、跨设备主题偏好、不同色彩模式、复杂主题资源按需加载，也无法为后续主题商品、授权和推荐机制提供稳定边界。

用户需要的是功能完全一致、但可以根据审美、使用场景和设备条件切换外观的 Lifly。默认体验必须极简、实用并以最快启动为首要目标；复杂主题可以包含更多资源并接受额外加载时间，但任何主题都不能阻塞核心功能、改变业务语义或破坏离线可用性。

如果直接在页面里继续增加颜色、圆角、间距和主题判断，客户端将形成大量分散的视觉常量和条件分支。后续每新增一个主题都需要修改业务页面，难以测试、难以跨端适配，也无法安全地支持远程主题包和商业授权。

## Solution

建设一个跨端 Flutter 主题应用框架，将主题定义、解析、安装、缓存、兼容检查、运行时切换、色彩模式、平台覆盖、受控布局变体和失败降级收敛到统一运行时。

Lifly 内置一个不可卸载的 `Lifly Core` 主题。它不依赖网络、远程资源、自定义字体或授权服务，并作为首次启动、资源加载、主题损坏、版本不兼容和授权异常时的最终兜底。应用首先以 Core 能力进入可操作状态，再恢复用户选择的复杂主题；复杂主题的下载、校验和增强资源加载不得阻塞 Core Shell 与本地数据访问。

远程主题采用声明式主题包，只包含经过约束的 manifest、设计令牌、静态资源、平台覆盖和预定义布局变体，不允许下载或执行任意 Dart 代码。主题功能与业务功能完全解耦，所有主题提供相同页面、字段、操作、同步、AI、审计和撤销能力。

主题框架为未来免费主题、单次购买、订阅主题、活动授权、账户级推荐和创作者生态预留协议，但 v0.8.0 只实现客户端运行时、Core 主题、测试主题和授权接口占位，不实现主题商店、支付或推荐算法。

## User Stories

1. As a Lifly user, I want the application to open with a usable interface without waiting for a theme server, so that I can access my data immediately.
2. As a Lifly user, I want a fast built-in default theme, so that the minimum installation has the smallest practical startup cost.
3. As a Lifly user, I want to select from multiple theme families, so that Lifly can match my visual preferences and usage context.
4. As a Lifly user, I want every theme to expose the same functionality, so that changing appearance never removes capabilities.
5. As a Lifly user, I want each theme to support appropriate color modes, so that I can use light, dark, system or other supported modes.
6. As a Lifly user, I want system color mode changes to update the active theme when I choose system mode, so that Lifly follows my device preference.
7. As a Lifly user, I want a manually selected color mode to remain stable, so that system changes do not override my explicit choice.
8. As a Lifly user, I want my account to remember my preferred theme, so that new devices can start from a familiar appearance.
9. As a Lifly user, I want a device-specific theme override, so that my work computer and phone can use different themes.
10. As a Lifly user, I want color mode to remain device-specific by default, so that each screen can use an appropriate mode.
11. As a Lifly user, I want an already installed paid theme to remain usable while temporarily offline, so that connectivity failures do not unexpectedly remove my appearance.
12. As a Lifly user, I want Lifly to fall back safely when a paid theme cannot be validated, so that I am never locked out of the application.
13. As a Lifly user, I want a complex theme to load after the core interface is usable, so that visual richness does not block productivity.
14. As a Lifly user, I want a locally cached complex theme to appear quickly on later launches, so that repeated use does not always show a long theme loading phase.
15. As a Lifly user, I want a theme loading failure to degrade quietly to a usable appearance, so that decorative resources do not generate disruptive error dialogs.
16. As a Lifly user, I want a previous working theme version to remain available after a failed update, so that an update cannot break the interface.
17. As a Lifly user, I want theme changes to preserve the current page and unsaved interaction state, so that changing appearance does not interrupt my work.
18. As a Lifly user, I want theme switching to provide immediate visual feedback, so that the setting feels responsive.
19. As a Lifly user, I want accessibility-critical labels and warnings to remain visible in every theme, so that compact themes do not hide necessary information.
20. As a keyboard user, I want focus indicators to remain clear in every Web and desktop theme, so that I can navigate without a pointer.
21. As a pointer user, I want Web themes to provide consistent hover and pressed states, so that interactive elements are discoverable.
22. As a mobile user, I want all themes to preserve adequate touch targets, so that visual density does not make controls difficult to use.
23. As a desktop user, I want compact themes to use screen space efficiently, so that lists and management pages remain practical.
24. As a user who prefers minimal interfaces, I want professional themes to reduce decorative and repetitive text, so that the interface emphasizes useful information.
25. As a user who prefers expressive interfaces, I want rich themes to use optional illustrations, typography and motion, so that Lifly can feel personal.
26. As a user on a low-performance device, I want the Core theme to avoid heavy visual resources, so that Lifly remains responsive.
27. As a user on a capable device, I want rich themes to be allowed to load enhanced resources, so that performance constraints do not eliminate visual variety.
28. As a user with reduced-motion preferences, I want theme motion to be reduced or disabled, so that the interface respects accessibility settings.
29. As a user, I want critical, warning, success and informational states to remain semantically consistent across themes, so that colors do not change the meaning of product states.
30. As a user, I want a theme to change density and approved layout variants without hiding business modules, so that themes can feel distinct without changing Lifly's product behavior.
31. As a user, I want theme previews to accurately represent supported color modes and platforms, so that I can make an informed selection in a future theme catalog.
32. As a user, I want incompatible themes to be rejected before application, so that an old theme cannot corrupt or destabilize a newer client.
33. As a user, I want corrupted theme resources to be detected, so that Lifly does not render a partially broken interface.
34. As a user, I want theme assets to be cached and reused, so that repeated launches do not require unnecessary downloads.
35. As a user, I want unused optional theme resources to avoid loading during Core startup, so that the default path stays fast.
36. As a user, I want theme updates to occur in the background, so that I can continue using the currently installed version.
37. As a user, I want a theme update to switch atomically only after all required files validate, so that I never see a mixed old-and-new theme.
38. As a user, I want the application to retain a known-good theme version, so that it can automatically roll back after an activation problem.
39. As a user, I want Web startup to show an immediate lightweight Lifly shell, so that the page does not appear blank while Flutter initializes.
40. As a user, I want locally available data to render before cloud synchronization completes, so that theme initialization does not weaken Lifly's local-first behavior.
41. As a product operator, I want theme packages to declare a stable identifier and version, so that installations and updates can be managed reliably.
42. As a product operator, I want themes to declare supported application versions, platforms, color modes and performance class, so that incompatible packages can be filtered.
43. As a product operator, I want themes to declare a fallback theme, so that failure behavior is deterministic.
44. As a product operator, I want themes to declare asset integrity metadata, so that modified or incomplete packages can be rejected.
45. As a product operator, I want official themes to be signed, so that the client can distinguish trusted packages.
46. As a product operator, I want free, purchase, subscription and promotional entitlement types represented without coupling them to rendering, so that commercial models can evolve independently.
47. As a product operator, I want theme recommendations to be added later without changing the runtime contract, so that catalog ranking remains separate from theme application.
48. As a theme designer, I want semantic design tokens instead of page-specific colors, so that one theme can style the whole product consistently.
49. As a theme designer, I want controlled platform overrides, so that the same theme family can adapt to Web, phone and desktop interaction patterns.
50. As a theme designer, I want approved layout variants, so that a theme can choose compact, balanced or dashboard presentation without arbitrary page rewrites.
51. As a theme designer, I want optional assets to have lightweight fallbacks, so that an unloaded illustration never leaves a broken layout.
52. As a developer, I want pages to consume theme semantics rather than hard-coded visual values, so that adding a theme does not require editing every page.
53. As a developer, I want a single theme runtime interface, so that manifest parsing, preference resolution, compatibility, caching and fallback can be tested through one high-level seam.
54. As a developer, I want remote themes to remain declarative, so that the application never executes untrusted theme code.
55. As a developer, I want plugin execution and theme rendering to remain separate systems, so that theme installation does not become a remote-code plugin mechanism.
56. As a developer, I want deterministic theme resolution, so that the same installed packages, entitlement state and preferences always produce the same active theme.
57. As a developer, I want malformed token values to be rejected or normalized at the runtime boundary, so that invalid data does not leak into widgets.
58. As a developer, I want optional theme resources to load asynchronously, so that the Core path remains independent of rich resources.
59. As a developer, I want theme changes to notify only the required widget subtree, so that switching themes does not cause unrelated service reinitialization.
60. As a QA engineer, I want fixtures for Core, standard, rich, invalid, incompatible and corrupted themes, so that all resolution branches can be verified.
61. As a QA engineer, I want Web, mobile and desktop tests to assert platform overrides, so that one platform's theme behavior does not regress another.
62. As a QA engineer, I want startup tests to verify that network and authorization failures do not block the Core Shell, so that the performance contract is protected.
63. As a QA engineer, I want accessibility tests to verify contrast, focus visibility, touch target size and reduced motion, so that decorative themes remain usable.
64. As a QA engineer, I want visual regression coverage for a small set of canonical theme surfaces, so that token changes do not accidentally break the product hierarchy.
65. As a release engineer, I want a Core startup performance gate, so that future theme additions cannot silently slow the default experience.
66. As a release engineer, I want package compatibility and integrity validation in release checks, so that invalid theme bundles are caught before distribution.

## Implementation Decisions

### Theme domain model

- A Theme Family represents a complete design language. It is independent from light or dark presentation.
- A Color Mode represents the active palette mode within a Theme Family. The framework initially recognizes system, light, dark, OLED and high-contrast semantics, while each theme declares which modes it supports.
- A Theme Package is an installable and versioned distribution unit containing a manifest, semantic tokens, optional assets, platform overrides, previews and compatibility metadata.
- `Lifly Core` is a built-in Theme Family and Theme Package. It is always available, cannot be removed, requires no entitlement and is the terminal fallback.
- Theme Entitlement represents whether an account may use a package. Rendering consumes only an entitlement result and does not know whether access came from a free grant, purchase, subscription, promotion or another commercial mechanism.
- Theme Preference has an account-level default Theme Family and a device-level override. Color Mode remains device-local by default.
- Theme Recommendation is a separate future concern that ranks or suggests themes but does not change the active theme without user action.

### Theme package contract

- Every package has a stable theme identifier and immutable semantic identity across versions.
- Every package declares its package version, display metadata, author, minimum supported application version, supported platforms, supported color modes, performance class, required and optional assets, fallback theme identifier, entitlement type and integrity metadata.
- Official packages are signed. The runtime verifies signature and integrity before activation.
- The package format is declarative. It may contain data and resources but cannot contain remotely executable Dart code.
- Future third-party metadata may be represented in the manifest, but v0.8.0 accepts only built-in or Lifly-official trusted packages.
- Required assets must validate before a package version becomes active. Optional assets can fail independently and use declared lightweight fallbacks.
- Package updates are installed into a new version slot, validated, preloaded at the required level and activated atomically. The current known-good version is retained until the new version succeeds.

### Semantic token model

- Product widgets consume semantic tokens rather than theme-specific or page-specific raw constants.
- Token groups include color, typography, spacing, radius, elevation, density, motion, icon style, surface style and focus style.
- Status tokens preserve the meaning of critical, warning, success, informational, disabled and neutral states across all themes.
- Tokens have a validated schema and supported value ranges. Unknown required tokens reject the package; unknown optional tokens are ignored for forward compatibility.
- The framework supplies Core defaults for every token. Theme packages may override allowed tokens but cannot remove required semantics.
- System fonts are used by Core. Custom fonts are optional rich resources and cannot block Core startup.
- Reduced-motion and accessibility preferences override theme motion tokens.

### Controlled layout variants

- Themes may select only framework-defined layout variants such as compact, balanced or dashboard.
- Layout variants can alter density, spacing, card arrangement and approved responsive compositions.
- Layout variants cannot remove required modules, hide critical states, change permissions, reorder safety-critical actions or replace product behavior.
- Platform-specific layout overrides are allowed only through declared, validated variants.
- Page ownership remains with product features. Themes style and select approved presentation variants; they do not supply arbitrary page implementations.

### Platform adaptation

- The same Theme Family and semantic contract are shared by Flutter Web, phone and desktop clients.
- Platform overrides may adjust pointer hover, focus rings, side navigation density, touch target sizing, bottom navigation presentation, window density and keyboard interactions.
- Platform overrides cannot change data contracts or feature availability.
- Web is the first complete validation platform, but the runtime API and package resolver must not depend on browser-only concepts.

### Runtime architecture

- A single Theme Runtime is the primary application seam. It resolves preferences, installed package versions, compatibility, entitlement state, platform, color mode and fallback into an active immutable theme snapshot.
- The Theme Runtime exposes observable active state and explicit loading, ready, degraded and failed-to-Core states.
- The active snapshot contains validated tokens, resolved assets, platform overrides, layout variants, package identity and diagnostic metadata.
- Widgets consume the active snapshot through the shared application theme boundary. Theme changes do not recreate API, synchronization, Local Core or AI services.
- Preference resolution is deterministic: device override, account preference and Core fallback follow a documented precedence order.
- Color mode resolution is deterministic: explicit device mode takes precedence; system mode resolves from the current platform brightness; unsupported modes fall back according to the package manifest and ultimately Core.
- Runtime failures are contained. An invalid preference, missing package, invalid signature, incompatible version, entitlement failure or asset failure cannot prevent the Core theme from becoming active.

### Startup and loading strategy

- Core startup never waits for network, account entitlement, remote package metadata, theme recommendation, cloud synchronization or rich assets.
- The Web host presents a lightweight immediate Lifly startup shell before the Flutter first frame.
- Flutter presents the Core Shell as soon as the application runtime is ready.
- Local preference and cached known-good theme state are restored asynchronously without delaying the first usable Core frame.
- If a compatible cached theme is ready, the runtime applies it after Core initialization with minimal visual discontinuity.
- If a theme is not cached, the runtime continues with Core while downloading and validating the requested package in the background.
- Complex themes may declare standard or rich performance classes and accept additional first-use loading time. This never relaxes the Core performance budget.
- Optional heavy modules or official effects may use compile-time deferred loading where supported, but online theme packages remain declarative resources rather than deferred executable theme code.
- Local-first data loading and PowerSync connection continue independently from theme enhancement loading.

### Failure and fallback strategy

- The resolution chain is: requested compatible known-good version, prior known-good version, declared compatible fallback, Lifly Core.
- Theme download, validation and activation are transactional from the user's perspective.
- Failed updates do not replace the active known-good version.
- Missing optional resources use lightweight fallbacks without blocking activation when package rules allow it.
- Theme degradation is reported through diagnostics and settings, not through blocking startup dialogs.
- The runtime records enough non-sensitive diagnostics to explain why Core or another fallback became active.

### Entitlement and offline behavior

- v0.8.0 defines an entitlement-provider interface and local entitlement result model but does not implement payments or a production theme authorization service.
- Built-in Core and test themes use local deterministic entitlement fixtures.
- A previously downloaded paid theme may remain usable offline when a recent valid entitlement grant exists.
- The exact commercial offline grace period is intentionally deferred to the commercialization phase.
- Entitlement failure never blocks application entry and never deletes local user data.

### Preference synchronization

- Account preference and device override are separate values.
- Account preference is designed to synchronize through the existing account and data synchronization architecture in a later implementation slice.
- Device override and Color Mode are stored locally and remain effective when offline.
- A device override takes precedence over the account preference on that device.
- Removing a device override reveals the current account preference without resetting package installations.

### Security boundary

- Theme packages are content, not plugins.
- The theme runtime never evaluates scripts, dynamically loads remote Dart or exposes arbitrary file or network execution to theme data.
- Remote resource references must pass scheme, origin, integrity, size and type policy checks before use.
- Package extraction and cache paths must prevent traversal and overwrite outside the theme cache.
- Theme data cannot supply accessibility labels, business copy, API paths, database queries or executable expressions.
- Future plugin support, if added, requires a separate architecture and security review.

### Performance contract

- Core has no remote theme dependency, no custom font dependency, no large decorative asset dependency and no complex continuous animation dependency.
- The first performance target is the earliest usable Shell, not completion of cloud synchronization or rich theme activation.
- The initial working budgets are: immediate Web host feedback within 300 ms where the browser permits, usable desktop-broadband Core Shell within 2.5 seconds, usable simulated-4G Core Shell within 4 seconds, cached repeat startup within 1.5 seconds, navigation feedback within 100 ms and ordinary transition completion within 300 ms.
- These budgets are starting gates and must be measured on reproducible hardware/network profiles before release criteria are finalized.
- Default JavaScript/CanvasKit and WebAssembly/skwasm builds are compared using the same startup and interaction scenarios before choosing the production renderer strategy.
- Rich theme performance is measured separately and cannot be used to weaken Core gates.

### Version scope and sequencing

- v0.8.0 delivers the cross-platform theme runtime, package contract, Lifly Core, a non-default fixture theme, failure fallback, color mode handling, local preference persistence, Web startup shell and release checks.
- Web Shell visual restructuring and product-page redesign follow in later v0.8.x slices after the runtime contract is stable.
- A fixture theme exists only to prove multiple-theme resolution, platform overrides, color modes, asset fallback and runtime switching; it is not a finished commercial theme.

## Testing Decisions

- Tests assert externally observable behavior and public runtime state, not private helper calls, cache implementation details or widget tree internals.
- The primary domain seam is the Theme Runtime. Given installed package metadata, preferences, entitlement state, platform, system brightness and failure conditions, tests assert the resulting active theme snapshot and diagnostic state.
- The primary user-visible seam is the application Shell. Tests assert that Core becomes usable without network or rich-theme readiness, that selecting a theme changes visible semantics without losing navigation state, and that failures return to a usable Core presentation.
- Manifest contract tests cover valid packages, missing required fields, unknown optional fields, invalid token values, unsupported application versions, unsupported platforms, invalid signatures, integrity mismatches, missing required assets and missing optional assets.
- Resolution tests cover device override precedence, account preference fallback, unsupported Color Mode fallback, previous known-good rollback, declared fallback and terminal Core fallback.
- Loading-state tests cover Core-first startup, cached-theme activation, background download, optional-resource degradation, failed update and atomic successful update.
- Security tests cover path traversal, disallowed resource schemes, oversized resources, unsupported content types and attempts to supply executable or business-behavior fields.
- Widget tests cover theme switching, light/dark/system response, preserved current destination, Web focus visibility, compact text behavior, mobile touch target preservation and reduced motion.
- Golden or screenshot tests are limited to canonical surfaces: application Shell, status semantics, form controls, list rows, cards and one responsive dashboard composition. They do not snapshot every page and theme combination.
- Performance checks use release/profile Web builds rather than debug mode. They record host feedback, Flutter first frame, Core Shell usable time, cached-theme activation time and navigation response.
- JavaScript/CanvasKit and WebAssembly/skwasm builds are tested against identical fixtures before renderer selection.
- Existing Flutter widget-test and repository-test patterns are reused. New test helpers provide deterministic package repositories, entitlement providers, preference stores and platform context without coupling tests to concrete storage.
- A release gate verifies that Core contains no remote theme dependency, all required Core tokens exist, package fixtures validate, failure scenarios reach Core and business pages do not introduce new hard-coded theme values outside approved compatibility boundaries.

## Out of Scope

- A production theme store or catalog UI.
- Payment processing, subscription billing or purchase restoration.
- A production server-side entitlement API.
- Final offline entitlement grace-period policy.
- Theme recommendation algorithms or automatic theme switching.
- Third-party creator submission, review, moderation or revenue sharing.
- Arbitrary user-imported themes in the first release.
- Remote Dart code, executable scripts or theme-provided plugins.
- A general plugin framework.
- Finished commercial theme families beyond Lifly Core.
- Full Web Shell redesign and all product-page UI/UX redesigns.
- Service-side changes unrelated to the future theme catalog, entitlement or preference synchronization contract.
- Replacing the existing local-first, PowerSync or repository architecture.
- Allowing themes to change business rules, feature availability, security warnings, audit behavior or data contracts.

## Further Notes

- The canonical product term is `Theme Family`; light and dark are `Color Modes`, not independent theme families.
- The canonical built-in fallback is `Lifly Core`.
- “Professional” or compact themes reduce decorative and repetitive text but must retain labels, errors, warnings, accessibility semantics and operation results.
- Rich themes are allowed to load more slowly, but the Core startup path remains the product-wide performance baseline.
- Theme framework and theme commercialization are deliberately separated so that UI development can proceed without prematurely coupling rendering to payment infrastructure.
- This document is a temporary execution plan. After implementation, durable conclusions must be written back to the architecture, client design, testing, current-status and roadmap documents, then this plan must be removed.
