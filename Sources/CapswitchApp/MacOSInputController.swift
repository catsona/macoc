import AppKit
import ApplicationServices
import CapswitchCore
import CapswitchHID
import CoreGraphics
import Foundation

enum InputControllerError: LocalizedError {
    case accessibilityRequired
    case inputMonitoringRequired
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required. Open the Capswitch menu to grant it."
        case .inputMonitoringRequired:
            return "Keyboard tap refused. Grant Input Monitoring from the Capswitch menu."
        case .eventTapUnavailable:
            return "macOS did not allow the keyboard event tap. Check Accessibility and Input Monitoring permissions."
        }
    }
}

final class MacOSInputController {
    private let inputSources = InputSourceManager()
    private let remapper = HIDRemappingController()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var inputRouter = CapsInputRouter()

    private(set) var observedF19Down = 0
    private(set) var observedF19Up = 0
    private(set) var successfulSwitches = 0
    private(set) var capsLockToggles = 0

    var isPaused = false
    var lastError: String?
    var onStateChanged: (() -> Void)?

    var isRunning: Bool {
        isTapEnabled && remapper.isInstalled
    }

    var isTapEnabled: Bool {
        guard let eventTap else {
            return false
        }
        return CFMachPortIsValid(eventTap) && CGEvent.tapIsEnabled(tap: eventTap)
    }

    var inputMonitoringTrusted: Bool {
        CGPreflightListenEventAccess()
    }

    var hidMappingConfigured: Bool {
        remapper.isInstalled
    }

    var mappingStatus: String {
        "\(remapper.mappedServiceCount)/\(remapper.keyboardServiceCount) keyboards"
    }

    // Undocumented macOS preference: only diagnostic, never modified by us.
    // Missing means unknown, not off.
    var nativeCapsSwitchState: String {
        let value = UserDefaults.standard.object(forKey: "TISRomanSwitchState")
            ?? UserDefaults(suiteName: "com.apple.HIToolbox")?
                .object(forKey: "TISRomanSwitchState")

        guard let number = value as? NSNumber else {
            return "Unknown (check Keyboard settings)"
        }

        return number.intValue == 0 ? "Off" : "On - disable for Capswitch"
    }

    var currentInputSourceName: String {
        inputSources.currentDisplayName
    }

    var currentInputSourceShortName: String {
        inputSources.currentShortName
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    var diagnosticsSummary: String {
        "F19 ↓\(observedF19Down) ↑\(observedF19Up) · switches \(successfulSwitches)"
    }

    func start() throws {
        guard !isPaused, eventTap == nil else {
            return
        }

        guard accessibilityTrusted else {
            throw InputControllerError.accessibilityRequired
        }

        // Active .defaultTap filtering is authorized through Accessibility
        // on many macOS versions. Try that first; Input Monitoring is an
        // additional diagnostic/grant path if tap creation is refused.
        // Enumerate input sources before entering the event tap callback.
        inputSources.refresh()

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            throw inputMonitoringTrusted
                ? InputControllerError.eventTapUnavailable
                : InputControllerError.inputMonitoringRequired
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            tap,
            0
        )

        if let runLoopSource {
            CFRunLoopAddSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        resetGestureState()

        // Only remap the physical Caps once we know our intercept is active.
        do {
            try remapper.ensureInstalled()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            stop()
            throw error
        }

        onStateChanged?()
    }

    @discardableResult
    func stop() -> Bool {
        // Restore the actual Caps key before disabling the F19 interceptor.
        // If restoration fails, refuse a normal Pause/Quit so F19 cannot be
        // left unhandled by an otherwise healthy running Capswitch.
        do {
            try remapper.restoreIfOwned()
        } catch {
            lastError = "Cannot restore Caps remap: \(error.localizedDescription)"
            onStateChanged?()
            return false
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }

        eventTap = nil
        runLoopSource = nil
        resetGestureState()
        onStateChanged?()
        return true
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }

        if paused {
            if stop() {
                isPaused = true
            }
        } else {
            isPaused = false
            do {
                try start()
            } catch {
                lastError = error.localizedDescription
            }
        }
        onStateChanged?()
    }

    func refreshInputSources() {
        inputSources.refresh()
    }

    // macOS can silently disable taps after a timeout or permission change.
    // Detect that before considering the HID mapping healthy.
    func repairEventTapIfNeeded() {
        guard let eventTap else {
            return
        }

        guard !isTapEnabled else {
            return
        }

        if CFMachPortIsValid(eventTap), accessibilityTrusted {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }

        if !isTapEnabled {
            lastError = "The keyboard event tap is disabled. Recheck macOS permissions."
            stop()
        }
    }

    func reapplyHIDMapping() {
        guard !isPaused, eventTap != nil, isTapEnabled else {
            lastError = "The keyboard event tap must be active before reapplying Caps → F19."
            onStateChanged?()
            return
        }

        do {
            try remapper.reapplyIfOwned()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        onStateChanged?()
    }

    func requestRequiredPermissions() {
        if !accessibilityTrusted {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:
                    true as CFBoolean
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        if !inputMonitoringTrusted {
            // Request Input Monitoring for our own application identity.
            _ = CGRequestListenEventAccess()
        }
    }

    func requestInputMonitoringPermission() {
        _ = CGRequestListenEventAccess()
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func openKeyboardSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.keyboard"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    func repairMappingIfNeeded() {
        guard !isPaused, eventTap != nil else {
            return
        }

        do {
            try remapper.ensureInstalled()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            // Never keep swallowing F19 if our mapping is no longer healthy.
            stop()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, refcon in

        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MacOSInputController>
            .fromOpaque(refcon)
            .takeUnretainedValue()

        return controller.handle(type: type, event: event)
    }

    private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGestureState()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let optionDown = event.flags.contains(.maskAlternate)

        if type == .flagsChanged {
            apply(inputRouter.flagsChanged(optionDown: optionDown))
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(
            truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)
        )

        // We own F19. Both the down and up must be suppressed so they do not
        // leak into the foreground app or its own keyboard shortcuts.
        guard keyCode == CapsInputRouter.f19VirtualKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !repeated {
                observedF19Down += 1
            }
            apply(inputRouter.keyDown(
                code: keyCode,
                optionDown: optionDown,
                isRepeat: repeated
            ))
        } else {
            observedF19Up += 1
            apply(inputRouter.keyUp(code: keyCode, optionDown: optionDown))
        }

        return nil
    }

    private func apply(_ action: GestureAction) {
        switch action {
        case .none:
            break

        case .switchToNextInputSource:
            // Synchronous: the next typed letter must see the new layout.
            if inputSources.selectNextInputSource() {
                successfulSwitches += 1
                DispatchQueue.main.async { [weak self] in
                    self?.onStateChanged?()
                }
            } else {
                lastError = "Unable to select the next enabled input source."
            }

        case .toggleCapsLock:
            toggleRealCapsLock()
        }
    }

    private func toggleRealCapsLock() {
        var locked = false
        let readStatus = CapswitchReadCapsLock(&locked)

        if readStatus != 0 {
            locked = CGEventSource.flagsState(.combinedSessionState)
                .contains(.maskAlphaShift)
        }

        let writeStatus = CapswitchWriteCapsLock(!locked)
        if writeStatus == 0 {
            capsLockToggles += 1
        } else {
            lastError = "IOKit Caps Lock toggle failed (code \(writeStatus))."
        }

        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?()
        }
    }

    private func resetGestureState() {
        inputRouter.reset()
    }
}
