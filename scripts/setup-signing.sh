#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
macos_only

if security find-identity -v -p codesigning 2>/dev/null |
    grep -F '"macoc Local Signing"' >/dev/null; then
  echo "macoc Local Signing is already available in your Keychain."
  exit 0
fi

cat <<'INSTRUCTIONS'
One-time local signing identity setup (preserves Accessibility approval
across rebuilt versions, not needed for a plain app restart):

1. Open Keychain Access -> Certificate Assistant -> Create a Certificate.
2. Name: macoc Local Signing
3. Identity type: Self Signed Root; Certificate type: Code Signing.
4. Create it in your login keychain; permit codesign access when prompted.
5. Verify: security find-identity -v -p codesigning

The normal build automatically uses "macoc Local Signing" if available.
You can also set MACOC_CODESIGN_IDENTITY to a valid existing identity.
No private signing keys are generated/stored in this repository.

Apple:
https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html
INSTRUCTIONS
open -a "Keychain Access" || true
