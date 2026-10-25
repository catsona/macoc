# Capswitch

A small native macOS menu-bar app that uses Caps Lock to switch to the next enabled keyboard input source.

## Behavior

- Plain Caps: switch once on release.
- Caps+Option in either order: preserve real Caps Lock.
- Stock Caps/input-source events are suppressed.
- The app has no Dock icon and reports Accessibility permission in its menu.

## Build on macOS

The Linux RSB host cannot compile AppKit or run Swift/XCTest. On macOS 14+ with Apple's Command Line Tools installed:

```bash
xcode-select --install
task bundle
open build/Capswitch.app
```

No Xcode project or full Xcode.app is required.

Grant the app access at **System Settings → Privacy & Security → Accessibility**. Keep the bundle identifier and installation path stable so macOS can retain the permission.

## Development commands

```bash
task lint
task test
task build
task bundle
task clean
task verify
```

The authoritative checks are `task test` and `task bundle` on macOS. Linux runs only host-independent checks and reports the missing Swift/macOS toolchain explicitly.
