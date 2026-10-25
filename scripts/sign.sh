#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

if [[ ! -d "$APP_PATH" ]]; then
  echo "Bundle missing: $APP_PATH" >&2
  exit 1
fi
identity="${MACOC_CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null |
      grep -F '"macoc Local Signing"' >/dev/null; then
    identity="macoc Local Signing"
  else
    identity="-"
    echo "WARNING: ad-hoc signing may require Accessibility reapproval after rebuilding." >&2
    echo "Run bash scripts/setup-signing.sh for a persistent local identity." >&2
  fi
fi

echo "Signing identity: $identity"
if [[ "$identity" == Developer\ ID\ Application:* ]]; then
  # Developer ID builds require Hardened Runtime and a secure timestamp.
  # Notarization still requires a separate submission with Apple credentials.
  codesign --force --sign "$identity" --identifier "$BUNDLE_ID" \
    --options runtime --timestamp "$APP_PATH"
else
  codesign --force --sign "$identity" --identifier "$BUNDLE_ID" \
    --timestamp=none "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"
codesign --display --requirements - "$APP_PATH" 2>&1 | head -15
