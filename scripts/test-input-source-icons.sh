#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only
cd "$ROOT"

test_dir="$(mktemp -d "${TMPDIR:-/tmp}/macoc-icon-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -warnings-as-errors \
  -module-cache-path "${CLANG_MODULE_CACHE_PATH:-$ROOT/.build/icon-test-module-cache}" \
  Sources/CapswitchApp/InputSourceIconProvider.swift \
  Tests/CapswitchAppTests/InputSourceIconTests.swift \
  -o "$test_dir/input-source-icon-tests"
"$test_dir/input-source-icon-tests"
