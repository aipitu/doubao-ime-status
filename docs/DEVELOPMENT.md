# 开发指南

**中文** | [English](DEVELOPMENT.en.md) · [README](../README.md)

## macOS 原生构建

需要 macOS 13+、Xcode 或 Command Line Tools（Swift 5.9+）、Python 3。GitHub CI 使用 macOS 15 runner 自带的 Xcode。`xcode-select --install` 可安装命令行工具。

```bash
bash scripts/test-core.sh
bash scripts/build-macos.sh
python3 scripts/verify-artifact.py dist/DoubaoCaret.app
python3 Tests/test-artifact.py
python3 Tests/test-release.py
open dist/DoubaoCaret.app
```

在 Xcode 打开 `Package.swift` 可以编辑代码。构建脚本会产生带 Info.plist、图标和许可证的完整 `.app`；仅用 `swift build` 得到的可执行文件不等于可分发的应用包。测试权限时，请将 `.app` 放入固定的 `/Applications` 路径。

本机已有固定代码签名证书时：

```bash
SIGN_IDENTITY='你的代码签名身份' bash scripts/build-macos.sh
```

默认使用 ad-hoc 签名。开发构建不自动公证；正式 CI 签名见 [发布指南](RELEASING.md)。

## Linux 交叉编译

宿主要求 Linux x86_64、Docker、Python 3、curl、tar、xz，建议至少 6 GB 可用空间。Docker 镜像和 SDK 只保存在本机构建缓存。

```bash
bash scripts/setup-cross.sh
bash scripts/build-linux.sh
python3 scripts/verify-artifact.py dist/DoubaoCaret.app
python3 Tests/test-artifact.py
python3 Tests/test-release.py
docker run --rm -v "$PWD:/work" -w /work swift:6.1.2-jammy bash scripts/test-core.sh
```

工具链：固定 digest 的 Swift 6.1.2 Linux 镜像、macOS 15.5 SDK、Darwin LLD、rcodesign。下载有校验值；SDK 的 Clang/libxml 路径修复记录在 setup 脚本。SDK 受 Apple 条款约束，不提交或随 Release 分发。Linux 无法运行 AppKit/WindowServer，交叉编译通过不代表完成 macOS GUI 验收。

## 目录

| 路径 | 职责 |
|---|---|
| `Sources/DoubaoCaret/Core.swift` | 平台无关状态机、位置和几何校验 |
| `IMEDetector.swift` | 输入源、豆包窗口证据和状态校准 |
| `Accessibility.swift` | AX 串行队列、焦点和 caret 获取 |
| `InputMonitor.swift` | listen-only 键盘/鼠标事件 |
| `Overlay.swift` | 非激活、鼠标穿透面板 |
| `Preferences.swift` / `SettingsWindow.swift` | 持久化设置及预览 |
| `PermissionsWindow.swift` | 授权导航与修复命令复制 |
| `AppDelegate.swift` / `main.swift` | 菜单、系统生命周期和入口 |
| `Resources/` | Info.plist、图标及源 PNG |
| `Tests/` | 状态、坐标、包篡改与发布工具测试 |
| `scripts/` | 构建、签名、公证、打包和发布准备 |

除 `Core.swift` 外，上表简写的 Swift 文件均在 `Sources/DoubaoCaret/`。

## 修改原则与验证

- 不从缺失候选窗推出英文；未知状态保留为未知。
- 不用焦点控件原点、整行选区或推算字符位置冒充 caret。
- 不读取输入文字，不注入键盘事件，不扫描整棵 AX 树。
- 跨进程 AX 调用留在串行 worker，保留范围/超时限制和 mouse fallback。
- 图标已作为资源提交，普通构建不需要 Pillow。仅重新转换图标时运行 `python3 scripts/make-icon.py`。

`--smoke-test` 启动菜单栏应用并在约 2 秒后退出，不显示首次设置窗口或主动申请权限。它验证启动路径，不能证明真实 IME、caret、全屏和 CPU 表现。手动检查见 [VALIDATION.md](VALIDATION.md)，检测依据见 [RESEARCH.md](RESEARCH.md)。

改版本时同步 plist 与 changelog，再执行 `python3 scripts/validate-version.py`。提交工作流前建议运行 `actionlint .github/workflows/*.yml`。本地调研日志、SDK、构建包和证书不提交。
