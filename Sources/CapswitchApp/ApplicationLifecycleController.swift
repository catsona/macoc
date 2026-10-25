import Foundation
import ServiceManagement

enum ApplicationLifecycleError: LocalizedError {
    case missingExecutable
    case couldNotRestoreCaps(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "Unable to locate the bundled macoc executable."
        case let .couldNotRestoreCaps(details):
            return "Caps Lock was not restored: \(details)"
        }
    }
}

/// Owns the app-level transitions. All exit/restart paths first restore Caps
/// via the same HID controller used by Pause and Quit.
final class ApplicationLifecycleController {
    private let inputController: MacOSInputController
    private let installer = AppInstallationManager()
    private let loginItems = LoginItemManager()

    init(inputController: MacOSInputController) {
        self.inputController = inputController
    }

    var isInstalled: Bool {
        installer.isRunningInstalledCopy
    }

    var loginItemStatus: SMAppService.Status {
        loginItems.status
    }

    var loginItemTitle: String {
        loginItems.title
    }

    func toggleLaunchAtLogin() throws {
        try loginItems.toggle(isRunningInstalledCopy: isInstalled)
    }

    func install() throws -> URL {
        try installer.install()
    }

    func restartCurrentCopy() throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw ApplicationLifecycleError.missingExecutable
        }
        try relaunch(executableURL: executableURL)
    }

    func restartInstalledCopy(at applicationURL: URL) throws {
        let executableURL = applicationURL.appendingPathComponent("Contents/MacOS/macoc")
        try relaunch(executableURL: executableURL)
    }

    func stopForQuit() throws {
        guard inputController.stop() else {
            throw ApplicationLifecycleError.couldNotRestoreCaps(
                inputController.lastError ?? "Unknown IOKit error"
            )
        }
    }

    private func relaunch(executableURL: URL) throws {
        try stopForQuit()
        do {
            try ApplicationRelauncher.spawn(executableURL: executableURL)
        } catch {
            // Starting the replacement failed: resume the old app instead
            // of leaving a remapped keyboard with no active interceptor.
            do {
                try inputController.start()
            } catch {
                inputController.lastError =
                    "Relaunch and input recovery failed: \(error.localizedDescription)"
            }
            throw error
        }
    }
}
