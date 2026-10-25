#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

: "${FORGEJO_TOKEN:?Forgejo release requires FORGEJO_TOKEN}"
: "${FORGEJO_SERVER_URL:?Forgejo release requires FORGEJO_SERVER_URL}"
: "${FORGEJO_REPOSITORY:?Forgejo release requires FORGEJO_REPOSITORY}"

tag="${FORGEJO_REF_NAME:-${GITHUB_REF_NAME:-}}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a version tag like v0.3.0, got: $tag" >&2
  exit 1
fi

if [[ "$FORGEJO_REPOSITORY" != "catsona/macoc" ]]; then
  echo "Unexpected repository: $FORGEJO_REPOSITORY" >&2
  exit 1
fi

release_api="$FORGEJO_SERVER_URL/api/v1/repos/$FORGEJO_REPOSITORY/releases"
json_file="$(mktemp)"
auth_file="$(mktemp)"
chmod 600 "$auth_file"
# Avoid placing the short-lived repository token in curl's argv/process list.
printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN" > "$auth_file"
trap 'rm -f "$json_file" "$auth_file"' EXIT

read_release() {
  curl -K "$auth_file" -fsS "$release_api/tags/$tag"
}

if ! read_release > "$json_file" 2>/dev/null; then
  payload="$(python3 -c \
    'import json,sys; print(json.dumps({"tag_name":sys.argv[1], "name":sys.argv[1], "body":"macoc release for macOS. Unsigned / ad-hoc builds may require additional Gatekeeper approval. See README for signing and notarization.", "draft":False, "prerelease":False}))' \
    "$tag")"
  curl -K "$auth_file" -fsS -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" "$release_api" > "$json_file"
fi

release_id="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' < "$json_file")"
existing_assets="$(curl -K "$auth_file" -fsS \
  "$release_api/$release_id/assets")"

shopt -s nullglob
archives=("$DIST_PATH/macoc-$tag-macos-"*.zip)
if [[ "${#archives[@]}" -ne 1 ]]; then
  echo "Expected exactly one archive for $tag in $DIST_PATH" >&2
  exit 1
fi
assets=("${archives[0]}" "${archives[0]}.sha256")
if [[ ! -s "${assets[0]}" || ! -s "${assets[1]}" ]]; then
  echo "Missing archive/checksum pair for $tag" >&2
  exit 1
fi

for asset in "${assets[@]}"; do
  name="$(basename "$asset")"
  if printf '%s' "$existing_assets" | python3 -c \
    'import json,sys; name=sys.argv[1]; exit(0 if any(a.get("name")==name for a in json.load(sys.stdin)) else 1)' \
    "$name"; then
    echo "Already uploaded: $name"
    continue
  fi

  safe_name="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$name")"
  curl -K "$auth_file" -fsS -X POST \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$asset" \
    "$release_api/$release_id/assets?name=$safe_name" >/dev/null
  echo "Uploaded: $name"
done

echo "Published: $FORGEJO_SERVER_URL/$FORGEJO_REPOSITORY/releases/tag/$tag"
