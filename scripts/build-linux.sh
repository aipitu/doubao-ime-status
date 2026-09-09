#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for arch in arm64 x86_64; do
  docker run --rm \
    -v "$PWD:/work" -w /work -e ARCH="$arch" \
    swift:6.1.2-jammy@sha256:5910655d205a5a54b0b9efdf72c4066a8de1932513fdc81793e2544b5d5a0709 \
    bash scripts/compile-linux.sh
done
python3 scripts/package-app.py --universal build/arm64/DoubaoCaret build/x86_64/DoubaoCaret dist/DoubaoCaret.app
SIGNER="${RCODESIGN:-$PWD/.toolchain/apple-codesign/apple-codesign-0.29.0-x86_64-unknown-linux-musl/rcodesign}"
"$SIGNER" sign dist/DoubaoCaret.app
python3 scripts/package-app.py --zip-only dist/DoubaoCaret.app
python3 scripts/verify-artifact.py dist/DoubaoCaret.app
