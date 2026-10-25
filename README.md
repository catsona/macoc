# Capswitch

Native macOS menu-bar keyboard layout switcher, targeting macOS 14+.

- Plain physical Caps: switch to the next enabled input source on **release**,
  bypassing the stock Caps delay and input-source HUD.
- Caps + Option in either order: toggle the real system Caps Lock state.

## Architecture

The signed Capswitch executable itself uses IOKit to remap physical Caps
(HID usage 0x39) to F19 (usage 0x6E). Its active CoreGraphics event tap
suppresses F19 down/up events and switches through Carbon TIS on F19 release.
The small native C bridge is compiled into the app; there is no external
hidutil process, driver, helper, LaunchAgent or root component.

Apple API reference: https://developer.apple.com/library/archive/technotes/tn2450/

## Build, install and autostart

Install Apple's Command Line Tools and the Task runner. Full Xcode is not
required. Quit any running Capswitch from its status-bar menu before rebuilding.

For development:

    git pull origin main
    task test
    task bundle
    open build/Capswitch.app

For daily use, install without sudo into ~/Applications/Capswitch.app:

    git pull origin main
    task test
    task install

The Taskfile builds, installs and opens the installed copy.

Alternatively, open the development build and choose **Install to
~/Applications...** in the menu. Capswitch copies itself and restarts into the
installed copy. If an older installed Capswitch is still running, quit it
before reinstalling. Only bundles with the same bundle ID can be replaced.

From the installed copy, click **Launch at Login** in the menu. This uses
Apple's SMAppService.mainApp, not an ad-hoc LaunchAgent. If the menu says
approval required, open **General -> Login Items** in System Settings and
approve Capswitch. Click the same menu item to disable auto-start.
Launch at Login is disabled for development builds to avoid registering
a temporary build/ path.

The menu also has **Restart Capswitch**. It restores the Caps HID mapping
before exiting and launches a new copy of the same executable after the
old process is gone.

The app has a stable bundle identifier (dev.local.Capswitch) and is signed
ad-hoc. macOS may require re-approval for Accessibility/Input Monitoring
when moving from build/ to ~/Applications or replacing an ad-hoc signature.

## Privacy permissions

On first launch the app requests permissions under its own identity:
- Accessibility to suppress F19.
- Input Monitoring when macOS needs it to observe keyboard events.

Grant permissions to Capswitch only. No system executable needs extra
permissions. Apple requires the user to approve them in System Settings.

Disable the stock macOS Caps layout toggle via
**System Settings -> Keyboard -> Text Input -> Edit ->
Use Caps Lock to switch to/from ABC**. Keep the key assigned to its normal
Caps Lock role in Modifier Keys (not No Action).
Capswitch does not secretly change these preferences.

## Menu and diagnostics

The status-bar menu shows current layout, native HID keyboard service
mapping count, event tap status, permission status and diagnostics.

    F19 down/up counts; input source switches

No typed characters are recorded. If F19 counts increase but switches do not,
inspect enabled TIS input sources. If counts remain zero, inspect the
HID mapping and event tap status. Pause/normal Quit restore the physical
Caps key and preserve unrelated keyboard mappings.

Read-only native diagnostic mode:

    task doctor

This executes Capswitch's own binary, not hidutil, and does not change keys.

## HID recovery and limitations

Capswitch preserves pre-existing key mappings and records ownership of
its added Caps-to-F19 pair per keyboard service. It removes only owned
pairs when paused or quit. A forcibly terminated app may leave a pair
active until next clean Capswitch launch/quit, keyboard service removal,
or reboot. To recover, reopen Capswitch and Quit normally.

If installation or restart fails to restore Caps, the app displays an
error instead of silently quitting. If macOS loses permission, it surfaces
that status in the menu.

Development tasks:

    task verify
    task lint
    task test
    task build
    task bundle
    task install
    task doctor
    task clean

The Linux RSB host can run static checks but has no Apple AppKit/IOKit SDK.
The macOS build and real keyboard behavior must be verified on macOS.
