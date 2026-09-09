# Detection and implementation notes

[中文](RESEARCH.md) | **English**

## Observable Doubao state

[input-indicator](https://github.com/jianzhoujz/input-indicator) documents indirect observation of Doubao mode: accessible “中 / 英” tooltips, candidate windows and standalone Shift. It does not treat the system's TIS source as the IME's internal language state. Its MIT notice is retained in this repository and shipped with the app.

DoubaoCaret independently structures these observations as a detector, serial AX worker and pure state machine. Exact tooltip labels are accepted; absent candidates never imply English. The detector limits access to the Doubao process and small high-layer tooltip regions. It does not read text-field contents, inject code or inspect private process memory. The project has not confirmed a directly usable public internal-mode API.

## Caret compatibility

[Electron's documentation](https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md) describes `AXManualAccessibility`. This app requests it for foreground VS Code/Cursor and restores an explicitly observed prior false value when leaving; it does not edit configuration files.

[Chromium's accessibility implementation](https://chromium.googlesource.com/chromium/src/+/c9b7d1eaffddbb766bb331938b76d57bae9ca285/content/browser/accessibility/browser_accessibility_cocoa.mm) includes text-marker ranges and bounds. Optional AX string attributes are queried without private framework symbols. A zero-length selection is required before accepting marker bounds.

Application and system-wide focus paths are checked without scanning child trees. Caret bounds are checked against the owning window where available, because virtual textareas may have tiny or absent frames. Reasonable block-caret widths are accepted; selection spans and off-screen bounds are rejected. The fallback remains the mouse.

## Platform choices

- Accessibility provides focus/range information; cross-process work runs on a serial queue.
- A listen-only CGEvent tap observes input activity without modifying events.
- A nonactivating NSPanel uses click-through and fullscreen/Space collection behaviors.
- `SMAppService.mainApp` manages login launch.
- Lang Cursor is a functional interaction reference; no proprietary code/assets are copied.

## Cross-compilation

Linux Swift generates Darwin Mach-O objects against the macOS SDK; Darwin LLD links them and rcodesign seals the app. The local setup script records SDK checksums and Clang/libxml path adjustments. GitHub releases instead build natively on macOS. Neither approach substitutes for on-device caret/IME validation, and the Apple SDK is not distributed with the app.
