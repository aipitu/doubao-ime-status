#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo 'Linux x86_64 host required'; exit 1; }
mkdir -p .toolchain/downloads
download() {
  local url="$1" destination="$2" digest="$3"
  if [[ ! -f "$destination" ]] || ! echo "$digest  $destination" | sha256sum -c - >/dev/null 2>&1; then
    curl -fL --retry 3 "$url" -o "$destination"
  fi
  echo "$digest  $destination" | sha256sum -c -
}
download https://github.com/joseluisq/macosx-sdks/releases/download/15.5/MacOSX15.5.sdk.tar.xz \
  .toolchain/downloads/MacOSX15.5.sdk.tar.xz c15cf0f3f17d714d1aa5a642da8e118db53d79429eb015771ba816aa7c6c1cbd
download https://github.com/xtool-org/darwin-tools-linux-llvm/releases/download/v1.0.1/toolset-x86_64.tar.gz \
  .toolchain/downloads/darwin-tools.tar.gz 58f567cbea08afb89aaee5ca0c2200e6c9fe7c014022fe380f0188e940d8d071
download https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign/0.29.0/apple-codesign-0.29.0-x86_64-unknown-linux-musl.tar.gz \
  .toolchain/downloads/apple-codesign.tar.gz dbe85cedd8ee4217b64e9a0e4c2aef92ab8bcaaa41f20bde99781ff02e600002
if [[ ! -d .toolchain/MacOSX15.5.sdk ]]; then
  tar -xJf .toolchain/downloads/MacOSX15.5.sdk.tar.xz -C .toolchain
fi
mkdir -p .toolchain/darwin-tools .toolchain/apple-codesign
tar -xzf .toolchain/downloads/darwin-tools.tar.gz -C .toolchain/darwin-tools
tar -xzf .toolchain/downloads/apple-codesign.tar.gz -C .toolchain/apple-codesign
# Swift's transitive module builders locate Clang headers relative to resource-dir.
if [[ ! -L .toolchain/MacOSX15.5.sdk/usr/lib/swift/clang ]]; then
  ln -s /usr/lib/clang/17 .toolchain/MacOSX15.5.sdk/usr/lib/swift/clang
fi
# This SDK archive contains duplicate copies instead of one canonical libxml path.
if [[ ! -L .toolchain/MacOSX15.5.sdk/usr/include/libxml ]]; then
  mv .toolchain/MacOSX15.5.sdk/usr/include/libxml .toolchain/libxml-original
  ln -s libxml2/libxml .toolchain/MacOSX15.5.sdk/usr/include/libxml
fi
docker pull swift:6.1.2-jammy@sha256:5910655d205a5a54b0b9efdf72c4066a8de1932513fdc81793e2544b5d5a0709
echo 'Cross toolchain ready. Run bash scripts/build-linux.sh'
