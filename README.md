# Capswitch

Small native macOS menu-bar app. Physical Caps Lock is HID-remapped to F19, which Capswitch intercepts to select the next input source **on release**, including during continuous fast typing. Caps+Option retains the system Caps Lock function.

## Requirements

- macOS 14 or newer and Apple Command Line Tools (install with xcode-select --install).
- Task (Taskfile runner).
- Accessibility permission under **System Settings -> Privacy & Security -> Accessibility**.
- Disable **Keyboard -> Text Input -> Edit -> Use Caps Lock to switch to/from ABC**.
- Keep the Caps Lock key set to its normal role in **Keyboard -> Keyboard Shortcuts -> Modifier Keys**, not "No Action".
- No Xcode project, root helper, Karabiner or third-party driver is needed.

## Build and test on your Mac

**Quit the currently running Capswitch from its menu first.** Opening an already running app may activate an old process even if a new bundle was created. The Taskfile refuses to replace the app bundle while a Capswitch process is running.

~~~bash
git pull origin main
task test
task bundle
open build/Capswitch.app
~~~

Grant Accessibility permission and restart Capswitch if macOS prompts you to do so.

## Behavior

- Plain physical Caps emits F19 keyDown/keyUp. Capswitch swallows both events and on F19 keyUp selects the next enabled keyboard input source.
- Caps+Option in either order toggles the actual system Caps Lock state through IOKit after Option has been released.
- Pause from the menu disables the event tap and restores the Caps key to its original purpose.
- Quit normally restores only Capswitch's Caps->F19 mapping, leaving unrelated mappings alone.
- On wake or keyboard reconnection, Capswitch checks whether its HID mapping is still present.

## Diagnostics

Open the status-bar menu while testing quick typing. It displays:

    F19 ↓N ↑N · switches N

No typed text is recorded. If the F19 counts do not change, the HID remap is not producing F19 events. If they change but the switch count does not, inspect input source selection.

Caps+Option through IOKit and its LED behavior still require verification on an actual Mac.

## HID remapping safety

HID key mapping is global. Capswitch first reads existing mappings, refuses collisions involving Caps or F19, and preserves unrelated remaps. It removes only its own rule on normal Quit/Pause. A small ownership marker allows a later launch to restore a rule that Capswitch left behind after a crash.

If the app is forcibly terminated, Caps may remain mapped to F19 until the app is relaunched and Quit normally, or until reboot. To inspect mappings:

~~~bash
hidutil property --get UserKeyMapping
~~~

**Do not clear all UserKeyMapping rules if you use other remappers.** Only if the sole entry is the one Capswitch inserted may you reset mappings manually:

~~~bash
hidutil property --set '{"UserKeyMapping":[]}'
~~~

hidutil remapping normally resets after restart or after the last keyboard service disappears.

## Development

~~~bash
task lint
task test
task build
task bundle
task clean
task verify
~~~

Linux RSB runs host-independent static checks only. SwiftPM builds, XCTest, IOKit and actual keyboard input behavior must be verified on macOS with the Apple SDK.
