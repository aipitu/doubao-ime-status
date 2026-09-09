#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Use scripts/build-linux.sh for Linux → macOS cross-compilation.' >&2
  exit 1
fi
mkdir -p build/arm64 build/x86_64
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -whole-module-optimization \
    -target "$arch-apple-macosx13.0" -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    Sources/DoubaoCaret/*.swift -o "build/$arch/DoubaoCaret"
done
mkdir -p build/universal
xcrun lipo -create build/arm64/DoubaoCaret build/x86_64/DoubaoCaret -output build/universal/DoubaoCaret
python3 scripts/package-app.py build/universal/DoubaoCaret dist/DoubaoCaret.app
codesign --force --sign "${SIGN_IDENTITY:--}" dist/DoubaoCaret.app
codesign --verify --strict dist/DoubaoCaret.app
ditto -c -k --keepParent dist/DoubaoCaret.app dist/DoubaoCaret-macos-universal.zip
echo 'Built dist/DoubaoCaret.app'
