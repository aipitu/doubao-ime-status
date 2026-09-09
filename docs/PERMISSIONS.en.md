# Permissions and update identity

[中文](PERMISSIONS.md) | **English** · [README](../README.en.md)

## Why updates can invalidate permission

Default test builds are ad-hoc signed. macOS TCC checks code identity, not only the app's name or bundle ID. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) explains that an ad-hoc designated requirement is bound to the particular code version. After recompiling, an old permission may stop working even when System Settings still shows its switch enabled.

Keep `local.doubao-caret` and `/Applications/DoubaoCaret.app` stable, but a stable path alone does not fix changing ad-hoc identity. Do not weaken signing requirements to match only a bundle ID, modify the TCC database, or disable SIP.

## Simplified repair

Open **权限设置与更新修复** (Permissions and update repair) from the menu or settings:

1. Open the Accessibility and Input Monitoring pages separately and enable the app.
2. **重新检测权限** (Recheck permissions) restarts monitoring without resetting grants.
3. If an update left stale grants, use **复制本应用的权限修复命令** (Copy this app's repair commands), quit the app, and paste into Terminal. Grant the two permissions again after it reopens.

For the standard installation path, the commands are:

```bash
/usr/bin/tccutil reset Accessibility local.doubao-caret
/usr/bin/tccutil reset ListenEvent local.doubao-caret
/usr/bin/open '/Applications/DoubaoCaret.app' --args --permissions
```

No `sudo` is needed. These reset only this app's two grants, not other applications. They **cannot grant access automatically**. macOS requires your approval, and some versions may still need the app re-added or restarted. See [Apple's scoped reset documentation](https://developer.apple.com/documentation/xcode/resetting-access-to-protected-resources-in-macos).

## Preserve identity across releases

Use a stable Developer ID signing identity and Apple notarization for public distribution. With compatible bundle ID, signing requirements and installation path, the system can usually recognize updates. Notarization addresses distribution checks; stable signing identity is what supports permission continuity. The first transition from ad-hoc to a certificate identity may still require reauthorization.

A consistent local code-signing certificate, including a suitably configured self-signed certificate, may be useful for development. It is not Developer ID/notarization; validate TCC behavior on the target macOS. Keep private keys in your own Keychain, not in the repository.

For downloaded updates, use the provided local helper after quitting and replacing the app:

```bash
security find-identity -v -p codesigning
SIGN_IDENTITY='Your stable signing identity' bash scripts/sign-update-macos.sh /Applications/DoubaoCaret.app
```

Use the same identity each time. Source builds also support `SIGN_IDENTITY='…' bash scripts/build-macos.sh`. This project does not silently create or trust certificates. See [Release configuration](RELEASING.en.md) for signing and notarization in GitHub Actions.
