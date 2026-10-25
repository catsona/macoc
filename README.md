# Capswitch

Small native macOS menu-bar app. Physical Caps Lock is HID-remapped to F19, which Capswitch intercepts to select the next input source **on release**, including during continuous fast typing. Caps+Option retains the system Caps Lock function.

## Requirements

- macOS 14 or newer and Apple Command Line Tools (install with xcode-select --install).
- Task (Taskfile runner).
- Grant **Accessibility** under **System Settings -> Privacy & Security** to
  let the app suppress F19. On some macOS setups you may also need
  **Input Monitoring**. The menu shows both permissions separately and
  provides a grant action; active CGEventTap may work with Accessibility alone.
- **Important for users coming from the stock Caps switch:** Disable
  **Keyboard -> Text Input -> Edit -> Use Caps Lock to switch to/from ABC**
  while using Capswitch. That macOS shortcut must not compete with our own
  input-source selector. Capswitch does not change this setting automatically.
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

After opening Capswitch, grant **Accessibility** from the status-bar menu.
If the event tap is refused or no F19 events are received, also grant
**Input Monitoring** from the menu. Restart Capswitch after granting
permissions if macOS prompts you to do so.

If you previously used macOS's built-in Caps-to-input-source switching, open
System Settings -> Keyboard -> Text Input -> Edit and uncheck
"Use Caps Lock to switch to and from [last used Latin input source]".
Keep Caps assigned to the normal Caps Lock action in Modifier Keys.

Open the Capswitch menu and confirm:
- Accessibility: Granted
- Input Monitoring: Granted (or not granted if the active tap works)
- Event tap: Enabled
- HID Caps -> F19: configured

These confirm permissions and the global configuration, **not** yet that the
physical keyboard is actually sending F19. Use the counters to verify it.

## Behavior

- Plain physical Caps emits F19 keyDown/keyUp. Capswitch swallows both events and on F19 keyUp selects the next enabled keyboard input source.
- Caps+Option in either order toggles the actual system Caps Lock state through IOKit after Option has been released.
- Pause from the menu disables the event tap and restores the Caps key to its original purpose.
- Quit normally restores only Capswitch's Caps->F19 mapping, leaving unrelated mappings alone.
- On wake or keyboard reconnection, Capswitch checks whether its HID mapping is still present.

## Diagnostics

Open the status-bar menu while testing quick typing. It displays:

    F19 ↓N ↑N · switches N

No typed text is recorded. If the F19 counts do not change, the HID remap is not producing F19 events
or the event tap is not receiving them. First check both permissions, the
event tap status and the native Caps switch preference. Then use the
"Reapply Caps -> F19 mapping" menu action and repeat the test.

If F19 counts increase but switches do not, investigate TIS input-source
selection. If the stock Caps input switch still operates while Capswitch
is active, the HID remap may not be applied to your physical keyboard.

To gather diagnostics without logging any typed text:

~~~bash
task doctor
~~~

This prints the native Caps preference, global UserKeyMapping and the keyboard
service-specific mapping; these can differ even when hidutil exits successfully.

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
task doctor
~~~

Linux RSB runs host-independent static checks only. SwiftPM builds, XCTest, IOKit and actual keyboard input behavior must be verified on macOS with the Apple SDK.
