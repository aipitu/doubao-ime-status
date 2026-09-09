#!/usr/bin/env bash
# CI-only Developer ID signing and notarization. All inputs arrive via step env.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS required' >&2; exit 1; }
cd "$(dirname "$0")/.."
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGN_IDENTITY APPLE_NOTARY_KEY_P8_BASE64 APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER_ID; do
  [[ -n "${!name:-}" ]] || { echo "Required secret missing: $name" >&2; exit 1; }
done
[[ "$MACOS_SIGN_IDENTITY" == 'Developer ID Application:'* ]] || {
  echo 'MACOS_SIGN_IDENTITY must be a Developer ID Application certificate name.' >&2; exit 1;
}
umask 077
SIGNING_TEMP=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/doubao-signing.XXXXXX")
export SIGNING_TEMP
KEYCHAIN_PATH="$SIGNING_TEMP/signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  rm -rf "$SIGNING_TEMP"
}
trap cleanup EXIT
python3 - <<'PY'
import base64, os
from pathlib import Path
root = Path(os.environ['SIGNING_TEMP'])
for key, filename in [('MACOS_CERTIFICATE_P12_BASE64', 'certificate.p12'), ('APPLE_NOTARY_KEY_P8_BASE64', 'notary.p8')]:
    (root / filename).write_bytes(base64.b64decode(''.join(os.environ[key].split()), validate=True))
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 1800 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_TEMP/certificate.p12" -k "$KEYCHAIN_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
codesign --force --options runtime --timestamp --keychain "$KEYCHAIN_PATH" \
  --sign "$MACOS_SIGN_IDENTITY" --identifier local.doubao-caret dist/DoubaoCaret.app
codesign --verify --strict --verbose=2 dist/DoubaoCaret.app
ditto -c -k --keepParent dist/DoubaoCaret.app "$SIGNING_TEMP/notarize.zip"
xcrun notarytool submit "$SIGNING_TEMP/notarize.zip" \
  --key "$SIGNING_TEMP/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait --timeout 20m --output-format json > "$SIGNING_TEMP/notary-result.json"
python3 - <<'PY'
import json, os
from pathlib import Path
result = json.loads((Path(os.environ['SIGNING_TEMP']) / 'notary-result.json').read_text())
if result.get('status') != 'Accepted':
    raise SystemExit(f"Notarization failed: status={result.get('status')}, submission={result.get('id')}")
print('Apple notarization accepted')
PY
xcrun stapler staple dist/DoubaoCaret.app
xcrun stapler validate dist/DoubaoCaret.app
spctl --assess --type execute --verbose=2 dist/DoubaoCaret.app
# Replace the pre-notarization archive with the stapled app.
ditto -c -k --keepParent dist/DoubaoCaret.app dist/DoubaoCaret-macos-universal.zip
