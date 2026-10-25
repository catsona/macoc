import AppKit
import Darwin
import Foundation

if CommandLine.arguments.contains("--doctor") {
    // Read-only inspection uses the same native IOKit code as the GUI.
    // This command never changes mappings or starts an event tap.
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
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
