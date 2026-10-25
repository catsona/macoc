import Darwin
import Foundation

enum RelaunchError: LocalizedError {
    case missingBundle
    case failedToLaunch(Int32)

    var errorDescription: String? {
        switch self {
        case .missingBundle:
            return "The macoc .app bundle is not available."
        case let .failedToLaunch(code):
            return "LaunchServices could not restart macoc (open exit code \(code))."
        }
    }
}

/// Relaunch through LaunchServices, never by directly executing
/// Contents/MacOS/macoc. Direct binary execution can lose macOS app/TCC
/// identity and cause fresh Accessibility prompts.
///
/// /usr/bin/open only launches the signed app; it is not granted input
/// permissions and never interacts with the HID remapping.
enum ApplicationRelauncher {
    static func spawn(executableURL: URL) throws {
        let appURL = executableURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        guard appURL.pathExtension == "app",
              FileManager.default.fileExists(atPath: appURL.path),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RelaunchError.missingBundle
        }

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = [
            "-n", "-a", appURL.path,
            "--args", "--wait-for-pid=\(ProcessInfo.processInfo.processIdentifier)"
        ]
        launcher.standardOutput = FileHandle.nullDevice
        launcher.standardError = FileHandle.nullDevice
        try launcher.run()
        launcher.waitUntilExit()
        guard launcher.terminationStatus == 0 else {
            throw RelaunchError.failedToLaunch(launcher.terminationStatus)
        }
    }

    static func waitForPreviousProcess(_ parentPID: pid_t) -> Bool {
        guard parentPID > 1 else { return false }

        // New instance must not own the HID mapping until the old one exits.
        for _ in 0..<200 {
            if kill(parentPID, 0) == -1 {
                return errno == ESRCH
            }
            usleep(50_000)
        }
        return false
    }
}
