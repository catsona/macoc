#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
tag="${FORGEJO_REF_NAME:-${GITHUB_REF_NAME:-}}"
if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$tag" != "v$version" ]]; then
  echo "Tag $tag does not match Info.plist version v$version" >&2
  exit 1
fi

bash "$ROOT/scripts/bundle.sh"
mkdir -p "$DIST_PATH"
name="macoc-v${version}-macos-$(uname -m).zip"
ditto -c -k --keepParent "$APP_PATH" "$DIST_PATH/$name"
(
  cd "$DIST_PATH"
  shasum -a 256 "$name" > "$name.sha256"
)
echo "Release archive: $DIST_PATH/$name"
