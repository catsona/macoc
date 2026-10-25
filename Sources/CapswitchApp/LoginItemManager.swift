import Foundation
import ServiceManagement

enum LoginItemError: LocalizedError {
    case installFirst

    var errorDescription: String? {
        switch self {
        case .installFirst:
            return "Install Capswitch to ~/Applications before enabling launch at login."
        }
    }
}

/// Registers the main app, not a helper process or LaunchAgent plist.
struct LoginItemManager {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    var title: String {
        switch status {
        case .enabled, .notRegistered:
            return "Launch at Login"
        case .requiresApproval:
            return "Launch at Login - approval required"
        case .notFound:
            return "Launch at Login - unavailable"
        @unknown default:
            return "Launch at Login"
        }
    }

    func toggle(isRunningInstalledCopy: Bool) throws {
        guard isRunningInstalledCopy else {
            throw LoginItemError.installFirst
        }

        let service = SMAppService.mainApp
        switch service.status {
        case .enabled, .requiresApproval:
            try service.unregister()
        case .notRegistered, .notFound:
            try service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        @unknown default:
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
