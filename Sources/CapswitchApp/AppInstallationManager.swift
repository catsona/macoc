import AppKit
import Foundation

enum AppInstallationError: LocalizedError {
    case invalidSource
    case alreadyInstalled
    case destinationContainsAnotherApp
    case installedCopyRunning
    case unsafeDestination
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "Capswitch must be launched from a valid .app bundle."
        case .alreadyInstalled:
            return "This copy of Capswitch is already installed."
        case .destinationContainsAnotherApp:
            return "The destination contains another application. It will not be overwritten."
        case .installedCopyRunning:
            return "Quit the installed Capswitch first, then retry installation."
        case .unsafeDestination:
            return "The installation destination is a symbolic link. No files were changed."
        case let .rollbackFailed(backupPath):
            return "Could not restore the previous app. The backup is at: \(backupPath)"
        }
    }
}

/// Copies the currently running app to the user's Applications folder without
/// admin privileges. Copy to a staging path before replacing an older version.
final class AppInstallationManager {
    private let fileManager = FileManager.default
    private let expectedBundleID = "dev.local.Capswitch"

    var installedURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Capswitch.app", isDirectory: true)
    }

    var isRunningInstalledCopy: Bool {
        let current = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        return current == installedURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func install() throws -> URL {
        let source = Bundle.main.bundleURL.standardizedFileURL
        let destination = installedURL.standardizedFileURL

        guard source.pathExtension == "app",
              Bundle.main.bundleIdentifier == expectedBundleID,
              let executable = Bundle.main.executableURL,
              fileManager.isExecutableFile(atPath: executable.path) else {
            throw AppInstallationError.invalidSource
        }

        guard !isRunningInstalledCopy else {
            throw AppInstallationError.alreadyInstalled
        }

        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        // fileExists can follow links, including dangling links. Never
        // replace a symlink that points outside the user's Applications dir.
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            throw AppInstallationError.unsafeDestination
        }

        if fileManager.fileExists(atPath: destination.path) {
            guard Bundle(url: destination)?.bundleIdentifier == expectedBundleID else {
                throw AppInstallationError.destinationContainsAnotherApp
            }

            let runningInstalledCopy = NSRunningApplication.runningApplications(
                withBundleIdentifier: expectedBundleID
            ).contains { app in
                app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
                    == destination.resolvingSymlinksInPath().standardizedFileURL
            }
            if runningInstalledCopy {
                throw AppInstallationError.installedCopyRunning
            }
        }

        let token = UUID().uuidString
        let staging = parent.appendingPathComponent(
            ".Capswitch-stage-\(token).app", isDirectory: true
        )
        let backup = parent.appendingPathComponent(
            ".Capswitch-backup-\(token).app", isDirectory: true
        )

        defer {
            if fileManager.fileExists(atPath: staging.path) {
                try? fileManager.removeItem(at: staging)
            }
        }

        try fileManager.copyItem(at: source, to: staging)

        guard Bundle(url: staging)?.bundleIdentifier == expectedBundleID,
              fileManager.isExecutableFile(
                atPath: staging.appendingPathComponent("Contents/MacOS/Capswitch").path
              ) else {
            throw AppInstallationError.invalidSource
        }

        let hasPreviousCopy = fileManager.fileExists(atPath: destination.path)
        if hasPreviousCopy {
            try fileManager.moveItem(at: destination, to: backup)
        }

        do {
            try fileManager.moveItem(at: staging, to: destination)
        } catch {
            if hasPreviousCopy {
                do {
                    try fileManager.moveItem(at: backup, to: destination)
                } catch {
                    throw AppInstallationError.rollbackFailed(backup.path)
                }
            }
            throw error
        }

        if hasPreviousCopy {
            try? fileManager.removeItem(at: backup)
        }

        return destination
    }
}
