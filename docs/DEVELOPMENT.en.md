# Development

[中文](DEVELOPMENT.md) | **English** · [README](../README.en.md)

## Native macOS builds

Requires macOS 13+, Xcode or Command Line Tools (Swift 5.9+), and Python 3. CI uses Xcode provided by the macOS 15 runner. Install command-line tools with `xcode-select --install` if necessary.

```bash
bash scripts/test-core.sh
bash scripts/build-macos.sh
python3 scripts/verify-artifact.py dist/DoubaoCaret.app
python3 Tests/test-artifact.py
python3 Tests/test-release.py
open dist/DoubaoCaret.app
```

Open `Package.swift` in Xcode for editing. The script creates a complete `.app` with metadata, icon and licenses; a raw `swift build` executable is not a distributable application bundle. Use a stable `/Applications` path when testing permissions.

Use an existing local signing identity with:

```bash
SIGN_IDENTITY='Your code-signing identity' bash scripts/build-macos.sh
```

The default is ad-hoc signing. Local builds do not automatically notarize; see [Releasing](RELEASING.en.md) for the optional signed CI pipeline.

## Linux cross-compilation

Requires Linux x86_64, Docker, Python 3, curl, tar and xz. Allow at least 6 GB free space. SDK/tool downloads remain in local caches.

```bash
bash scripts/setup-cross.sh
bash scripts/build-linux.sh
python3 scripts/verify-artifact.py dist/DoubaoCaret.app
python3 Tests/test-artifact.py
python3 Tests/test-release.py
docker run --rm -v "$PWD:/work" -w /work swift:6.1.2-jammy bash scripts/test-core.sh
```

The pinned toolchain uses Swift 6.1.2 for Linux, macOS 15.5 SDK, Darwin LLD and rcodesign. Downloads are checksum-verified; SDK Clang/libxml path adjustments are recorded in the setup script. The SDK is subject to Apple's terms and is not committed or distributed. Linux cannot run AppKit/WindowServer, so compilation is not GUI validation.

## Source layout

Swift files below live in `Sources/DoubaoCaret/`:

| File/directory | Purpose |
|---|---|
| `Core.swift` | Platform-independent state transitions and geometry |
| `IMEDetector.swift` | Input source, observable Doubao evidence and calibration |
| `Accessibility.swift` | Serial AX worker, focus and caret queries |
| `InputMonitor.swift` | Listen-only keyboard/mouse events |
| `Overlay.swift` | Nonactivating, click-through panel |
| `Preferences.swift`, `SettingsWindow.swift` | Persisted settings and preview |
| `PermissionsWindow.swift` | Permission navigation and repair-command copying |
| `AppDelegate.swift`, `main.swift` | Menu, lifecycle and entry point |
| `Resources/` at repository root | Info.plist, app icon and source PNG |
| `Tests/` at repository root | State, geometry, tamper and release-tool tests |
| `scripts/` at repository root | Build, signing, notarization, packaging and release staging |

## Change and validation rules

- Missing candidates never imply English; unknown stays unknown.
- Do not substitute control origins, selection-line bounds or guessed character positions for a caret.
- Do not read user text, inject keyboard events or scan entire AX trees.
- Keep cross-process AX calls on the serial worker with bounded queries/timeouts and mouse fallback.
- The icon is checked in; normal builds do not need Pillow. Run `python3 scripts/make-icon.py` only to regenerate ICNS from the source PNG.

`--smoke-test` launches the menu bar app and exits after about two seconds without showing first-launch settings or requesting permissions. This tests startup, not actual IME/caret/fullscreen/CPU behavior. See [Validation](VALIDATION.en.md) and [Research](RESEARCH.en.md).

Keep the plist version and changelog consistent, and run `python3 scripts/validate-version.py`. Use `actionlint .github/workflows/*.yml` before submitting workflow changes. Do not commit local investigation logs, SDKs, build artifacts or credentials.
