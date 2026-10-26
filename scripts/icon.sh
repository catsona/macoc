#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

# The composited Sonoma icon is committed as 1024px RGBA. The transparent
# outer margins and squircle silhouette must be preserved at every scale.
# The art grid in AppIconGrid.svg is never embedded in production images.
master="$ROOT/Resources/AppIcon.png"
if [[ ! -s "$master" ]]; then
  echo "Missing icon master: $master" >&2
  exit 1
fi

iconset="$ROOT/build/macoc.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"

for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$master" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
done

for specification in "16 32" "32 64" "128 256" "256 512" "512 1024"; do
  read -r name pixels <<<"$specification"
  sips -s format png -z "$pixels" "$pixels" "$master" \
    --out "$iconset/icon_${name}x${name}@2x.png" >/dev/null
done

mkdir -p "$APP_PATH/Contents/Resources"
iconutil -c icns "$iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
