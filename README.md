# macoc

<p align="center">
  <img src="Resources/AppIcon-preview.png" alt="macoc icon - a furious programmer on a burning office chair" width="172">
</p>

Native macOS menu-bar layout switcher for macOS Sonoma (14+) without
the stock Caps Lock delay. Plain **Caps** switches to the next configured
input source on **release**, including during fast typing. **Option+Caps**
in either order toggles the real system Caps Lock state.

While switching is active, the Caps Lock LED indicates the input layout:
off for U.S. or ABC (en-US), on for every other input source, including other
English layouts. This does not change letter case; **Option+Caps** still
controls the real Caps Lock state. Pause and Quit restore the LED to that state.
The indicator follows changes made in the system input menu as well as Caps,
and refreshes every second to handle keyboard connections and wake from sleep.
It requires a keyboard exposing a writable HID Caps Lock LED; the diagnostics
line reports unsupported LEDs or IOKit access errors without disabling switching.

macoc keeps input switching simple. The icon is an SFW illustration
of exactly how frustrating the old Caps Lock behavior can feel.

## Architecture

Caps Lock is remapped to F19 via in-process Apple IOKit APIs, then suppressed
by a CoreGraphics event tap. Layouts switch through Carbon TIS. No drivers,
root daemons, third-party input libraries or hidutil permission required.

Apple technical note: https://developer.apple.com/library/archive/technotes/tn2450/

## App icon

The icon uses a 1024 x 1024 RGBA master with a centered 824 x 824
superellipse body and transparent margins. This matches the visual
balance of the macOS application icon grid without accidentally
shipping a square, white-backed image.

- [Full-resolution master](Resources/AppIcon.png) - the single source for
  the shipped classic Sonoma AppIcon.icns.
- [Editable source layout](Resources/AppIconArtwork.svg) - includes the
  artwork and the clipping geometry, without requiring a third-party
  image tool during app builds.
- [Non-shipping design grid](Resources/AppIconGrid.svg) - alignment lines,
  guides and 100px margins; never embedded in the icon.
- [Layout measurements](Resources/AppIconLayout.json) - canvas, silhouette,
  crop and inset values.
- [Illustration source](Resources/IconArtwork.jpg) - editable raster scene.

When running bash scripts/icon.sh (or task icon) on macOS, the build
uses sips to generate all ten Apple iconset PNG representations:
16, 32, 128, 256 and 512 points, each at 1x and 2x. iconutil
combines them into Contents/Resources/AppIcon.icns. The shipped master
already has transparency, a subtle edge shadow, and safe spacing.

This is a classic precomposed macOS 14 .icns, not the layered Icon
Composer format introduced for newer icon appearances.

Apple design references:
- [Apple Human Interface Guidelines - app icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple Design Resources - grids and templates](https://developer.apple.com/design/resources/)
- [Apple archive - iconset filenames and scales](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/IconSetType.html)

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

CI workflow: .forgejo/workflows/ci.yml. It uses the **existing Docker
runner** and the official Linux Swift image. Pushes to main run shell
validation and **actual XCTest for pure Swift core logic**. On version
tags it also checks the tag against the application version.

**Linux Docker cannot compile macOS .app binaries** because Apple AppKit,
IOKit and macOS SDK are unavailable there. Docker CI does not publish
nonexistent macOS binaries.

For a release archive, check out the tag on a real Mac and run
bash scripts/package.sh (or task package), then execute
bash scripts/publish-release.sh with a repository-scoped Forgejo token.
Fully automated macOS binary releases require a real Mac runner or another Mac build service.

Ad-hoc artifacts are suited to local evaluation; public distribution
requires Developer ID signing and Apple notarization.

## Diagnostics and recovery

The status-bar menu shows layout, keyboard HID mapping count, event-tap state,
permission grants, and F19 down/up counts (no typed characters are recorded).
Run bash scripts/doctor.sh for read-only native HID diagnostics.

Pause or Quit normally restores Caps and preserves unrelated remappings.
If the process is killed during a remap, restart and Quit normally; macOS
usually resets mappings when a keyboard service disappears or after reboot.

The Linux development VM verifies shell syntax and static source checks,
not macOS compilation or live TCC behavior.
