import CapswitchHID
import Foundation

enum HIDRemapError: LocalizedError {
    case failure(Int32)

    var errorDescription: String? {
        switch self {
        case let .failure(code):
            switch code {
            case 1:
                return "Not enough memory to manage keyboard mappings."
            case 2:
                return "Cannot access IOKit keyboard services. Check Capswitch's macOS privacy permissions."
            case 3:
                return "No HID keyboard services found. Connect a keyboard and retry."
            case 4:
                return "An existing keyboard mapping has an unsupported format. No unrelated mappings were changed."
            case 5:
                return "Caps Lock or F19 already has a conflicting mapping. Capswitch will not overwrite it."
            case 6:
                return "macOS rejected the native Caps → F19 mapping for a keyboard."
            case 7:
                return "A keyboard did not confirm the Caps → F19 mapping."
            case 8:
                return "Could not identify a keyboard service safely."
            default:
                return "Native IOKit keyboard remapping failed (code \(code))."
            }
        }
    }
}

/// Owns the native IOKit remapping manager inside Capswitch itself.
/// No subprocess, hidutil, privileged helper, driver or third-party library.
final class HIDRemappingController {
    private let manager: UnsafeMutableRawPointer?

    private(set) var isInstalled = false
    private(set) var keyboardServiceCount: UInt32 = 0
    private(set) var mappedServiceCount: UInt32 = 0

    init() {
        manager = CapswitchRemapperCreate()
    }

    deinit {
        if let manager {
            CapswitchRemapperDestroy(manager)
        }
    }

    func ensureInstalled() throws {
        guard let manager else {
            throw HIDRemapError.failure(1)
        }

        var keyboardCount: UInt32 = 0
        var mappedCount: UInt32 = 0
        let status = CapswitchRemapperApply(manager, &keyboardCount, &mappedCount)

        keyboardServiceCount = keyboardCount
        mappedServiceCount = mappedCount
        isInstalled = status == 0 && keyboardCount > 0
            && mappedCount == keyboardCount

        guard status == 0, isInstalled else {
            throw HIDRemapError.failure(status == 0 ? 7 : status)
        }
    }

    func reapplyIfOwned() throws {
        // Reconciliation is idempotent: the native layer checks every
        // keyboard and only installs missing mappings it can safely own.
        try ensureInstalled()
    }

    func inspect() throws {
        guard let manager else {
            throw HIDRemapError.failure(1)
        }

        var keyboardCount: UInt32 = 0
        var mappedCount: UInt32 = 0
        let status = CapswitchRemapperInspect(manager, &keyboardCount, &mappedCount)
        keyboardServiceCount = keyboardCount
        mappedServiceCount = mappedCount

        guard status == 0 else {
            throw HIDRemapError.failure(status)
        }
    }

    func restoreIfOwned() throws {
        guard let manager else {
            throw HIDRemapError.failure(1)
        }

        let status = CapswitchRemapperRestore(manager)
        guard status == 0 else {
            throw HIDRemapError.failure(status)
        }

        isInstalled = false
        keyboardServiceCount = 0
        mappedServiceCount = 0
    }
}
