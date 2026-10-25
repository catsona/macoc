#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "Missing icon source: $SOURCE_ICON" >&2
  exit 1
fi

iconset="$ROOT/build/macoc.iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$SOURCE_ICON" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
done
for specification in "16 32" "32 64" "128 256" "256 512" "512 1024"; do
  read -r name pixels <<<"$specification"
  sips -s format png -z "$pixels" "$pixels" "$SOURCE_ICON" \
    --out "$iconset/icon_${name}x${name}@2x.png" >/dev/null
done
mkdir -p "$APP_PATH/Contents/Resources"
iconutil -c icns "$iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
