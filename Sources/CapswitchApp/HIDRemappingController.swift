import Foundation
import CapswitchCore

enum HIDRemapError: LocalizedError {
    case conflictingMapping
    case unreadableMapping
    case verificationFailed
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .conflictingMapping:
            return "Caps Lock or F19 is already remapped. Disable the conflicting mapping first."
        case .unreadableMapping:
            return "Cannot safely read the existing HID key mappings; no changes were made."
        case .verificationFailed:
            return "hidutil did not apply Caps → F19. On macOS 14, grant Input Monitoring to /usr/bin/hidutil separately from Capswitch.app, then restart Capswitch."
        case let .commandFailed(details):
            return "hidutil failed: \(details)"
        }
    }
}

/// Owns only the Caps -> F19 rule. Other mappings are preserved both when
/// installing and when restoring on quit or Pause.
final class HIDRemappingController {
    private let markerKey = "CapswitchOwnsCapsF19Mapping"
    private let ourMapping = HIDMappingCodec.capsToF19

    private(set) var isInstalled = false
    private var ownsMapping = false

    func ensureInstalled() throws {
        let current = try readMappings()

        if current.contains(ourMapping) {
            // Adopt a rule left behind after Capswitch crashed. A pre-existing
            // user-managed Caps -> F19 rule has no marker and is never removed.
            ownsMapping = ownsMapping || UserDefaults.standard.bool(forKey: markerKey)
            if ownsMapping && !isInstalled {
                // Reapply once after a crash/relaunch. Global UserKeyMapping
                // may be present while a keyboard service still has no mapping.
                try writeMappings(current)
            }
            isInstalled = true
            return
        }

        // Do not overwrite Caps remapped to something else, F19 remapped away,
        // or a different physical key remapped to F19.
        if current.contains(where: {
            $0.source == HIDMappingCodec.capsUsage
                || $0.source == HIDMappingCodec.f19Usage
                || $0.destination == HIDMappingCodec.f19Usage
        }) {
            throw HIDRemapError.conflictingMapping
        }

        // The marker is written before modifying global HID state so the next
        // launch can clean up an interrupted installation after a crash.
        UserDefaults.standard.set(true, forKey: markerKey)
        try writeMappings(current + [ourMapping])

        guard try readMappings().contains(ourMapping) else {
            throw HIDRemapError.verificationFailed
        }

        ownsMapping = true
        isInstalled = true
    }

    func reapplyIfOwned() throws {
        guard ownsMapping || UserDefaults.standard.bool(forKey: markerKey) else {
            throw HIDRemapError.conflictingMapping
        }

        let current = try readMappings()
        guard current.contains(ourMapping) else {
            try ensureInstalled()
            return
        }

        // Re-broadcast the complete mapping table, never an empty replacement.
        try writeMappings(current)
        guard try readMappings().contains(ourMapping) else {
            throw HIDRemapError.verificationFailed
        }

        isInstalled = true
    }

    func restoreIfOwned() throws {
        guard ownsMapping || UserDefaults.standard.bool(forKey: markerKey) else {
            isInstalled = false
            return
        }

        let current = try readMappings()

        if current.contains(ourMapping) {
            // Remove only our exact pair, preserving any changes made by
            // another remapper while Capswitch was running.
            try writeMappings(current.filter { $0 != ourMapping })

            if try readMappings().contains(ourMapping) {
                throw HIDRemapError.verificationFailed
            }
        }

        ownsMapping = false
        isInstalled = false
        UserDefaults.standard.removeObject(forKey: markerKey)
    }

    private func readMappings() throws -> [HIDKeyMapping] {
        let output = try runHidutil(["property", "--get", "UserKeyMapping"])

        do {
            return try HIDMappingCodec.parse(output)
        } catch {
            throw HIDRemapError.unreadableMapping
        }
    }

    private func writeMappings(_ mappings: [HIDKeyMapping]) throws {
        let argument = try HIDMappingCodec.setArgument(mappings)
        _ = try runHidutil(["property", "--set", argument])
    }

    private func runHidutil(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw HIDRemapError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw HIDRemapError.commandFailed(
                message.isEmpty ? "exit code \(process.terminationStatus)" : message
            )
        }

        return String(decoding: data, as: UTF8.self)
    }
}
