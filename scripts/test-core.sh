#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc Sources/DoubaoCaret/Core.swift Tests/main.swift -o build/tests/core-tests
build/tests/core-tests
