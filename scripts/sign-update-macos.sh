#!/usr/bin/env bash
# Re-sign a downloaded build with the SAME existing local identity each update.
# Does not create/trust certificates, change TCC, or transmit private keys.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Run on your Mac.' >&2; exit 1; }
APP_PATH="${1:-/Applications/DoubaoCaret.app}"
[[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != - ]] || {
  echo 'Set SIGN_IDENTITY to an existing code-signing certificate name or SHA-1.' >&2
  echo 'List identities with: security find-identity -v -p codesigning' >&2
  exit 1
}
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" == local.doubao-caret ]] || {
  echo 'Expected the DoubaoCaret bundle.' >&2; exit 1;
}
if /usr/bin/pgrep -x DoubaoCaret >/dev/null; then
  echo 'Quit DoubaoCaret from its menu before signing the replacement app.' >&2; exit 1
fi
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier local.doubao-caret "$APP_PATH"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_PATH"
/usr/bin/codesign -d -r- "$APP_PATH"
echo 'Signed. Use the same identity and installation path for subsequent updates.'
echo 'The first transition from ad-hoc signing can still require reauthorization.'
