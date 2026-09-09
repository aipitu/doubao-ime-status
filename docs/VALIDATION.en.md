# Validation

[中文](VALIDATION.md) | **English**

## Automated coverage

- Platform-independent state/geometry regression checks cover Shift chords, uncertain events, focus changes, multi-screen coordinates and invalid caret rectangles.
- Universal builds and package verification check both architectures, minimum macOS version, entry point, system dependencies, signed code/resource hashes, ICNS representations and ZIP permissions/CRC.
- Tamper tests reject modified code, metadata, resources and icon data.
- Release tests cover tag/version validation, scoped changelog extraction and asset metadata/checksums.
- GitHub macOS CI adds Apple's signature verification and an AppKit startup smoke test. This does not verify actual Doubao mode or editor caret behavior.

## On-device checklist

1. Install into `/Applications`. Confirm menu-bar-only behavior, settings reopening and both permissions.
2. Select Doubao, type pinyin, and verify Chinese evidence. Toggle with standalone Shift and compare the indicator with actual output.
3. Test Shift+letter, selection/navigation chords, shortcuts, mouse clicks/scrolling, both Shift keys, long holds and rapid taps. These must not produce unjustified mode flips.
4. Change focus/Spaces without changing input source: keep the last known mode while rechecking. Changing the input source or waking may require calibration. Manual calibration must never inject input.
5. Test VS Code, Cursor, Terminal, iTerm, Chrome, Safari and JetBrains individually. Type, move the caret, click, scroll and select text. Unsupported or invalid caret information must fall back to the mouse instead of retaining stale geometry.
6. Test Follow Mouse, all four corners, positive/negative offsets, exact values, both labels/colors, size, opacity, background and radius. Preview and indicator should update immediately.
7. Click/drag/select through the indicator. The original app must retain focus and receive input.
8. Test multiple monitors to the left/right/above/below, scaling, main-screen changes, boundaries and monitor disconnection.
9. Test Spaces, fullscreen transitions, secure fields, lock/unlock, sleep/wake and disabled mode.
10. Register login launch, check the system login item and test an actual login; unregister and verify it stops launching.
11. Replace an ad-hoc build and test the permission repair UI. Resetting requires explicit user action and must affect only this app's two permissions.

## Performance evidence

Measure 60 seconds each of idle, typing, continuous mouse movement and disabled mode using Activity Monitor/Instruments. Record OS, hardware, Doubao/app versions, average/peak CPU and wakeups. An idle average below 1% is a suggested target, not a measured guarantee.

When reporting failures, include copied caret diagnostics and application versions without typed text or sensitive screenshots. Do not enable whole-tree scanning to hide a failed caret API. An inferred Shift state must not be described as directly read internal IME state.
