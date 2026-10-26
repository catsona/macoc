#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

if [[ "$IS_MACOS" == 1 ]]; then
  cd "$ROOT"
  bash "$ROOT/scripts/test-input-source-icons.sh"
  swift test
elif command -v swift >/dev/null 2>&1; then
  bash "$ROOT/scripts/test-linux-core.sh"
elif [[ "${MACOC_REQUIRE_SWIFT:-0}" == 1 ]]; then
  echo "ERROR: the CI requires Swift for Linux XCTest." >&2
  exit 1
else
  echo "SKIP: Swift is not installed on this Linux development host."
fi
