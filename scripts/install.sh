#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only
bash "$ROOT/scripts/bundle.sh"
"$APP_PATH/Contents/MacOS/macoc" --install
open -a "$HOME/Applications/macoc.app"
