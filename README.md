# macoc

Native macOS menu-bar layout switcher for macOS Sonoma (14+) without
the stock Caps Lock delay. Plain **Caps** switches to the next configured
input source on **release**, including during fast typing. **Option+Caps**
in either order toggles the real system Caps Lock state.

The icon is a SFW cartoon of someone thoroughly fed up with keyboard
layout switching, complete with a literally hot seat.

## Architecture

Caps Lock is remapped to F19 via in-process Apple IOKit APIs, then suppressed
by a CoreGraphics event tap. Layouts switch through Carbon TIS. No drivers,
root daemons, third-party input libraries or hidutil permission required.

Apple technical note: https://developer.apple.com/library/archive/technotes/tn2450/

## Build and install

Requires Apple's Command Line Tools (not the Xcode IDE). Task is optional.

Quit any running **macoc** or legacy **Capswitch** before rebuilding.
From this repository:

    git pull origin main
    bash scripts/test.sh
    bash scripts/install.sh

With Task installed:

    task test
    task install

Installation creates a signed macoc.app with the .icns icon in the stable
user-owned location ~/Applications/macoc.app, then starts it through
LaunchServices. No sudo is needed.

For development without installing: bash scripts/bundle.sh or task bundle.

The menu offers **Restart macoc**, **Install to ~/Applications…** and
**Launch at Login**, registered via Apple's SMAppService.mainApp. If macOS
requests approval, open System Settings -> General -> Login Items.

### Migrating from Capswitch

The name and executable are now macoc; the existing bundle identifier
remains dev.local.Capswitch to preserve old Accessibility grants and HID
ownership data where macOS permits. Do not run the old Capswitch and macoc
simultaneously. If the old ~/Applications/Capswitch.app is installed, quit
it and disable its Login Item before installing macoc. Then you may delete
the old app bundle.

## Code signing and repeat Accessibility prompts

Restart now uses LaunchServices (open -n -a) instead of executing a raw
binary under Contents/MacOS. That preserves the macOS .app attribution.

For identical app binaries at the same path, Accessibility approval normally
persists through restarts. But ad-hoc signing does **not** provide a stable
designated requirement across code changes: each rebuild may require
approval again.

For stable identity across **rebuilt versions**, create one persistent
local Code Signing certificate in Keychain Access named
**macoc Local Signing** (Certificate Assistant -> Create a Certificate ->
Self Signed Root -> Code Signing). Run bash scripts/setup-signing.sh or
task signing-setup for the instructions. The build auto-detects that identity,
or accepts MACOC_CODESIGN_IDENTITY for an existing signing certificate.
It falls back to ad-hoc signing with an explicit warning otherwise.

Moving to the installed path or changing the signer can still require
**one new approval**. Keep the signing identity and app path stable.

Reference: https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

macoc cannot silently grant itself TCC permissions. macOS still asks the
user to allow Accessibility (and optionally Input Monitoring) for the app,
not for a system binary.

Disable macOS's own "Use Caps Lock to switch to/from ABC" under
System Settings -> Keyboard -> Text Input -> Edit. Keep physical Caps
assigned its normal modifier role rather than No Action.

## Taskfile commands and shell equivalents

| Taskfile | No Task required |
| --- | --- |
| task lint | bash scripts/lint.sh |
| task test | bash scripts/test.sh |
| task verify | bash scripts/verify.sh |
| task build | bash scripts/build.sh |
| task icon | bash scripts/icon.sh |
| task sign | bash scripts/sign.sh |
| task bundle | bash scripts/bundle.sh |
| task install | bash scripts/install.sh |
| task doctor | bash scripts/doctor.sh |
| task clean | bash scripts/clean.sh |
| task package | bash scripts/package.sh |
| task publish | bash scripts/publish-release.sh |
| task signing-setup | bash scripts/setup-signing.sh |

## Forgejo CI and releases

The workflow at .forgejo/workflows/macos.yml builds and tests on pushes to
main. A pushed tag such as v0.3.0 also creates a Forgejo release with a
macOS .app ZIP and SHA-256 checksum, through the built-in scoped token.

**A real Mac Forgejo runner labelled macos is required.** The Linux server
cannot build AppKit or IOKit. See [CI setup](docs/ci.md). Until a Mac runner
is registered and its job succeeds, no release build has been produced.

A release archive signed ad-hoc is intended for local evaluation.
To distribute broadly without Gatekeeper warnings, use Developer ID
signing and Apple's notarization service (not yet configured here).

## Diagnostics and recovery

The status-bar menu shows layout, keyboard HID mapping count, event-tap state,
permission grants, and F19 down/up counts (no typed characters are recorded).
Run bash scripts/doctor.sh for read-only native HID diagnostics.

Pause or Quit normally restores Caps and preserves unrelated remappings.
If the process is killed during a remap, restart and Quit normally; macOS
usually resets mappings when a keyboard service disappears or after reboot.

The Linux development VM verifies shell syntax and static source checks,
not macOS compilation or live TCC behavior.
