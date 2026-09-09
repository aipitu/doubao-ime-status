# Changelog / 更新日志

Versions follow `vMAJOR.MINOR.PATCH` tags. Unreleased changes are not included in release notes.
版本使用 `v主版本.次版本.修订版本` 标签；Unreleased 内容不会混入已发布版本说明。

## [Unreleased]

## [0.1.2] - 2026-09-08

### 中文

- 新增权限管理窗口：辅助功能/输入监控入口、实时状态、重新检测和复制本应用的授权修复命令。
- 新增 macOS 应用图标，覆盖 16–1024 像素与 Retina。
- 新增固定本地签名身份的更新脚本。
- 提供中英文项目文档及标签驱动的 GitHub Release 工作流，支持可选 Developer ID 签名与公证。
- 已知限制：caret 依赖应用 AX 支持；ad-hoc 更新可能需要重新授权；准确率和 CPU 尚未完成全面真机验收。

### English

- Added a permission window with Accessibility/Input Monitoring shortcuts, live status, monitoring restart, and app-scoped repair commands.
- Added a native application icon with 16–1024 px and Retina representations.
- Added a local update-signing helper for a consistent signing identity.
- Added Chinese/English documentation and tag-driven GitHub Releases with optional Developer ID signing and notarization.
- Known limitations: caret support depends on the target app; ad-hoc updates may need reauthorization; comprehensive on-device accuracy and CPU validation is pending.

## [0.1.1] - 2026-09-08

### 中文

- 切换焦点且输入源未变时保留最近已知模式，并重新校验。
- 增加双路焦点、TextMarker、Electron 辅助功能及 block caret 兼容路径。
- 增加可复制的外部应用 caret 诊断；修复仍需目标设备验证。

### English

- Preserve the last known mode across focus changes when the input source is unchanged, then recheck.
- Add dual focus queries, TextMarker support, Electron accessibility activation, and block-caret geometry.
- Add copyable diagnostics for the last external app; target-device validation remains necessary.

## [0.1.0] - 2026-09-08

### 中文

- 初始 Swift/AppKit 菜单栏应用，豆包内部状态观察、caret 优先与鼠标 fallback。
- 可配置显示方向、偏移、文字、颜色、字体大小、透明度及背景，实时预览。
- 提供登录启动和 Linux → macOS 双架构交叉编译工具。

### English

- Initial Swift/AppKit menu bar app with observable Doubao mode detection and caret-first/mouse fallback placement.
- Configurable position, offsets, text, colors, font size, opacity, background, and live preview.
- Launch at login and Linux-to-macOS universal cross-compilation tooling.
