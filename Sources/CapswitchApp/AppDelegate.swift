import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Only one process may own the global Caps -> F19 mapping.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains(where: {
                    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                }) {
            NSApp.terminate(nil)
            return
        }

        statusBarController = StatusBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}
