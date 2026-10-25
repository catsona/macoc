#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only
if [[ ! -x "$APP_PATH/Contents/MacOS/macoc" ]]; then
  echo "Build the app with bash scripts/bundle.sh first." >&2
  exit 1
fi
"$APP_PATH/Contents/MacOS/macoc" --doctor
