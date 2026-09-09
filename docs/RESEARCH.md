# 检测与实现依据

**中文** | [English](RESEARCH.en.md)

调研日期：2026-09-08。当前开发环境是 Linux，没有豆包或 macOS GUI；下述豆包特征来自已有开源实现，不能冒充本机逆向或真机测试结论。

## 豆包信号

[input-indicator 源码](https://github.com/jianzhoujz/input-indicator/blob/main/Sources/DoubaoInputIndicator.swift)及其[调研记录](https://github.com/jianzhoujz/input-indicator/blob/main/AGENTS.md)报告：豆包的内部模式不等于 TIS 输入源，公开 IPC 未发现可用接口。它通过窄域 AX「中 / 英」提示、候选窗、独立 Shift 观察进行校准。该项目为 MIT，许可证已保留。

本项目采用相同的观察面，重新组织为独立检测器、串行 AX worker 和纯状态机。候选窗口缺席不会推断英文；不读取用户文本，不扫描整棵应用 AX 树。窗口筛选锁定 `com.bytedance.inputmethod.doubaoime` PID、高 layer 和尺寸；仅对提示范围命中的元素读取严格单字标签。

本项目额外限制每次子树读取总计最多 20 个节点、深度 3、单层最多 8 个子节点、60ms 截止时间及单次 AX 超时。候选证据要求近期字母输入并避开 Shift 后冷却期。AX 提示冲突时放弃。提示窗口重复利用相同 ID 时仍会重新读取，避免只追踪新窗口导致漏判。

没有证据时显示未知；不能从「没有候选窗」推出英文，不能从 TIS 的 pinyin ID 推出中文，也不能把 Shift+字母、Shift+点击、Shift+滚动当作独立 Shift。

## 原生平台接口

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)：焦点元素、选区范围及参数化 bounds。优先应用 root 获取焦点，system-wide 作备选，并检查 PID。
- [只读 CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgeventtapoptions/listenonly)：监听输入活动，不吞键、不注入按键。
- [NSWindow fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)：与 canJoinAllSpaces 配合的非激活悬浮面板。
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)：系统登录启动注册，无 LaunchAgent 文件拼装。
- [Lang Cursor](https://apps.apple.com/mw/app/lang-cursor/id6767431292)：作为方向、offset、文字和颜色设置的功能参考，未获取或复制其专有实现。

## 0.1.1 caret 兼容修复

- [Electron 官方辅助功能说明](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md)提供 `AXManualAccessibility` 外部启用接口。本版对前台 VS Code / Cursor 按需请求，并在离开时恢复原先明确为 false 的设置；其他应用不设置该属性。
- [Chromium 的 AX 协议实现](https://chromium.googlesource.com/chromium/src/+/c9b7d1eaffddbb766bb331938b76d57bae9ca285/content/browser/accessibility/browser_accessibility_cocoa.mm)支持 TextMarker 选区和 bounds。本版以可选字符串属性查询，先确认长度为零，再接收坐标。接口不可用时继续 fallback，不链接私有 framework，不复制相关项目代码。
- 应用 focus 的非空结果不再阻挡 system-wide focus 的读取；只沿焦点关系最多四层，不扫描子树。
- 输入控件自身的几何信息缺失不再否定有效的 caret；优先使用所属窗口进行边界校验，容许合理宽度的 block caret，但拒绝整行/离屏矩形。
- 用户报告 0.1.0 可正常启动及显示输入状态，但所有应用只跟随鼠标。仅凭该反馈尚不能确定其设备上具体失败的 AX 接口，本版新增可复制的外部应用诊断。0.1.1 的实际 caret 跟随仍需用户验证。

## 跨平台构建细节

[Swift 的跨编译机制](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0387-cross-compilation-destinations.md)允许独立配置目标 SDK 与工具。本项目直接调用 Linux swiftc 生成 Mach-O object，避免 SwiftPM 的宿主链接器自动探测。

使用 [macosx-sdks 的 15.5 SDK](https://github.com/joseluisq/macosx-sdks/releases/tag/15.5)和 [xtool Darwin LLD](https://github.com/xtool-org/darwin-tools-linux-llvm/releases/tag/v1.0.1)。Swift resource-dir 指向 SDK，Clang builtin headers 使用 Linux Swift 工具链配套目录；SDK 归档里的两份 libxml headers 改为同一真实路径，消除重复模块。修复只作用于本地 SDK 缓存，不改应用系统接口。
