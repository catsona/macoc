# Capswitch

Native macOS menu-bar keyboard layout switcher, targeting macOS 14+.

**Caps**: switch to the next enabled input source **on release**, without
macOS's stock Caps delay or input-source HUD.

**Caps + Option** in either order: toggle the actual system Caps Lock state.

## How it works

Capswitch uses **IOKit APIs inside its own process** to remap physical HID
Caps Lock (usage 0x39) to F19 (usage 0x6E). Its active CoreGraphics event tap
intercepts F19 down/up and suppresses them, switching layouts on F19 release.
A small C bridge built into Capswitch contains the IOKit calls required by
Swift. There is **no subprocess**, no hidutil dependency, no external helper,
no driver, and no requirement to give permissions to a system executable.

Apple documents the direct APIs used for remapping in Technical Note TN2450:
https://developer.apple.com/library/archive/technotes/tn2450/

## Build on your Mac

Install Command Line Tools and the Task runner. Full Xcode is not needed.

**Quit any running Capswitch from the menu before rebuilding.** An already
running process won't be replaced merely by opening a new .app file.

~~~
git pull origin main
task test
task bundle
open build/Capswitch.app
~~~

The bundle is ad-hoc signed with a stable bundle identifier
(dev.local.Capswitch). Keep its installed path stable so macOS can retain
its privacy grants.

## Permissions - Capswitch only

At first launch Capswitch requests access via macOS:
- **Accessibility**: needed for an active event tap that suppresses F19.
- **Input Monitoring**, if macOS requires it: needed on some macOS setups
  for observing keyboard events or interacting with the HID subsystem.

Approve Capswitch.app, *never* /usr/bin/hidutil. macOS requires your own
confirmation in System Settings; applications cannot grant themselves access.

You can check/access those settings through the Capswitch menu. If granting
a permission requires a restart, Quit and reopen Capswitch.

To avoid competing with the stock shortcut, disable
**System Settings -> Keyboard -> Text Input -> Edit ->
Use Caps Lock to switch to/from ABC**. Leave Caps Lock with its normal
Caps Lock modifier role (not "No Action") in Keyboard Shortcuts -> Modifier Keys.
Capswitch never secretly changes these system preferences.

## Status menu

The menu shows:
- Current layout
- Native HID keyboard mapping count (e.g. 2/2 keyboards)
- Whether the keyboard event tap is enabled
- Accessibility and Input Monitoring grants
- F19 down/up and input-source switch counters (no typed text is recorded)
- Errors and a manual "Retry Caps -> F19 mapping" action
- Pause (restores Caps) and Quit (restores Caps)

When testing fast typing, repeatedly tap Caps while typing letters. If F19
counts increase but the switch counter doesn't, check the enabled TIS sources.
If the F19 counters remain zero, check the event tap, privacy grants, and HID
keyboard service count in the menu.

## Native diagnostics

~~~
task doctor
~~~

This executes **Capswitch's own signed executable** in a read-only inspection
mode and reports the number of HID keyboard services and how many have
Caps->F19 configured. It does not launch hidutil and does not change keyboard
configuration. The command requires an existing app bundle.

## HID safety

Capswitch reads **each keyboard service's existing mappings**, refuses
conflicting mappings involving Caps or F19, and preserves unrelated mappings.
It remembers which services it modified, storing their registry IDs in the
app's own preferences for crash recovery.

During Pause or normal Quit it removes only the exact Caps->F19 rule from
those services. Newly connected keyboards are handled when the app refreshes
its HID state. If Capswitch is forcibly killed, its mapping may remain until
the next successful Capswitch launch/quit, keyboard service removal, or reboot.
If the IOKit service rejects a mapping, Capswitch shows an error rather than
silently claiming success.

If you need to recover, use the menu's Pause/Quit action after restarting
Capswitch. In an emergency reboot macOS to clear HID remappings. Do not
blindly clear other programs' mapping tables.

## Development

~~~
task verify
task lint
task test
task build
task bundle
task doctor
task clean
~~~

The Linux RSB host can run static checks but has no Apple AppKit/IOKit SDK.
The final Swift build and real keyboard tests must be run on macOS.
