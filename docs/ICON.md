# 应用图标

**中文** | [English](ICON.en.md)

- 原始 PNG：`Resources/AppIcon-source.png`，保留生成结果及透明通道。
- macOS 图标：`Resources/AppIcon.icns`，11 个 PNG 表示，覆盖 16–1024 px 和 Retina 槽位。
- `CFBundleIconFile` 引用 AppIcon.icns；打包脚本将其复制进 Contents/Resources，并纳入资源签名。
- 再生成 ICNS：`python3 scripts/make-icon.py`（需要 Pillow，仅做尺寸与格式转换）。普通应用构建直接使用现有 ICNS，无需 Pillow。
- 使用内置 image_gen 工具生成，没有调用 CLI/API fallback。没有复制豆包的官方 logo。

最终生成提示词：

> Use case: logo-brand. Create one polished native macOS application icon for DoubaoCaret, a small developer utility displaying Chinese/English input mode near the text insertion caret. Square 1024x1024 PNG, genuinely transparent background outside the icon silhouette. A single centered rounded-square graphite/navy app tile occupying about 84% of the canvas, front-on, with subtle premium macOS dimensional bevel and restrained soft lighting. Inside: one bold crisp mint-green Chinese character exactly '中', alongside a slim pale-blue text insertion I-beam caret. Highly legible at 32 pixels, balanced generous spacing, simple confident geometry, understated developer-tool aesthetic. No additional text, no app name, no watermark, no environment, no perspective tilt, no Doubao corporate mascot or logos. The artwork is the finished icon asset, not an icon displayed inside a screenshot.
