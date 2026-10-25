#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only
cd "$ROOT"
swift build -c release
