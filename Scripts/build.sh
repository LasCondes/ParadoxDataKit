#!/usr/bin/env bash
set -euo pipefail
MODULE_CACHE="$(cd "$(dirname "$0")/.." && pwd)/.swiftpm/modulecache"
mkdir -p "$MODULE_CACHE"
export SWIFT_MODULE_CACHE_PATH="$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
exec swift build "$@"
