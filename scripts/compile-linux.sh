#!/usr/bin/env bash
# Run inside the pinned Swift container; no Darwin executables are invoked.
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${MACOS_SDK_PATH:-$PWD/.toolchain/MacOSX15.5.sdk}"
LINKER="${DARWIN_LINKER:-$PWD/.toolchain/darwin-tools/bin/ld64.lld}"
ARCH="${ARCH:-arm64}"
mkdir -p "build/$ARCH" .toolchain/module-cache
swiftc -swift-version 5 -O -whole-module-optimization \
  -target "$ARCH-apple-macosx13.0" -sdk "$SDK" \
  -resource-dir "$SDK/usr/lib/swift" -Xcc -resource-dir -Xcc "$(clang -print-resource-dir)" \
  -module-cache-path "$PWD/.toolchain/module-cache" \
  -emit-object Sources/DoubaoCaret/*.swift -o "build/$ARCH/DoubaoCaret.o"
"$LINKER" -arch "$ARCH" -platform_version macos 13.0 15.5 \
  -syslibroot "$SDK" -L "$SDK/usr/lib/swift" \
  -o "build/$ARCH/DoubaoCaret" "build/$ARCH/DoubaoCaret.o" \
  -lSystem -rpath /usr/lib/swift -adhoc_codesign
