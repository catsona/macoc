import AppKit
import CapswitchCore
import Darwin
import Foundation

let arguments = LaunchArguments(arguments: Array(CommandLine.arguments.dropFirst()))

switch arguments {
case .doctor:
    // Uses the same read-only native IOKit inspector as the running app.
    let remapper = HIDRemappingController()
    do {
        try remapper.inspect()
        print("Capswitch - native HID diagnostic")
        print("Keyboard services: \(remapper.keyboardServiceCount)")
        print("Caps → F19 mappings: \(remapper.mappedServiceCount)")
        if remapper.mappedServiceCount == remapper.keyboardServiceCount {
            print("Result: all detected keyboard services map Caps to F19")
        } else {
            print("Result: Caps → F19 is missing on at least one keyboard")
        }
        exit(0)
    } catch {
        fputs("Capswitch HID check: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case .install:
    do {
        let location = try AppInstallationManager().install()
        print("Installed Capswitch: \(location.path)")
        exit(0)
    } catch {
        fputs("Capswitch install: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

case let .waitForParent(pid):
    guard ApplicationRelauncher.waitForPreviousProcess(pid) else {
        fputs("Capswitch restart aborted: previous instance did not exit.\n", stderr)
        exit(1)
    }

case .application:
    break
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
