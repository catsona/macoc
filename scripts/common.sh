#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME=macoc
BUNDLE_ID=dev.local.Capswitch
APP_PATH="$ROOT/build/macoc.app"
SOURCE_ICON="$ROOT/Resources/IconSource.jpg"
DIST_PATH="$ROOT/dist"

if [[ "$(uname -s)" == Darwin ]]; then IS_MACOS=1; else IS_MACOS=0; fi

macos_only() {
  if [[ "$IS_MACOS" != 1 ]]; then
    echo "SKIP: this task requires macOS with Apple Command Line Tools."
    exit 0
  fi
}
