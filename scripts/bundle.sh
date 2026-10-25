#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

if pgrep -x macoc >/dev/null 2>&1 || pgrep -x Capswitch >/dev/null 2>&1; then
  echo "Quit any running macoc/Capswitch before rebuilding." >&2
  exit 1
fi

bash "$ROOT/scripts/build.sh"

bin_dir="$(cd "$ROOT" && swift build -c release --show-bin-path)"
binary="$bin_dir/macoc"
if [[ ! -x "$binary" ]]; then
  echo "SwiftPM did not produce the macoc executable: $binary" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$binary" "$APP_PATH/Contents/MacOS/macoc"
cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
bash "$ROOT/scripts/icon.sh"
bash "$ROOT/scripts/sign.sh"
echo "Built: $APP_PATH"
