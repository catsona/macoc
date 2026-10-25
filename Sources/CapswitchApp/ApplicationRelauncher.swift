import Darwin
import Foundation

enum RelaunchError: LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "The application executable was not found."
        }
    }
}

/// Starts the same bundled executable. The child waits for the old PID to
/// disappear before starting AppKit or the HID remapper.
enum ApplicationRelauncher {
    static func spawn(executableURL: URL) throws {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RelaunchError.missingExecutable
        }

        let child = Process()
        child.executableURL = executableURL
        child.arguments = [
            "--wait-for-pid=\(ProcessInfo.processInfo.processIdentifier)"
        ]
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
    }

    static func waitForPreviousProcess(_ parentPID: pid_t) -> Bool {
        guard parentPID > 1 else {
            return false
        }

        // Bounded wait: never start a second keyboard remapper when the
        // original application refuses to terminate.
        for _ in 0..<200 {
            if kill(parentPID, 0) == -1 {
                return errno == ESRCH
            }
            usleep(50_000)
        }
        return false
    }
}
