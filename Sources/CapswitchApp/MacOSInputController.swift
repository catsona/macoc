import AppKit
import CapswitchCore
import CapswitchHID
import ApplicationServices
import Carbon
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

final class InputSourceManager {
    private struct Source {
        let inputSource: TISInputSource
        let id: String
    }

    private var orderedSources: [Source] = []

    var currentDisplayName: String {
        guard let source = currentSource() else {
            return "-"
        }
        return property(source, key: kTISPropertyLocalizedName)
            ?? property(source, key: kTISPropertyInputSourceID)
            ?? "-"
    }

    var currentShortName: String {
        let name = currentDisplayName
        if let first = name.split(whereSeparator: { $0 == " " || $0 == "-" }).first,
           !first.isEmpty {
            return String(first).uppercased()
        }
        return name
    }

    func refresh() {
        orderedSources = enabledKeyboardSourcesInUserOrder()
    }

    @discardableResult
    func selectNextInputSource() -> Bool {
        let sources = orderedSources
        guard sources.count > 1 else {
            return false
        }

        let currentID = currentSource().flatMap {
            property($0, key: kTISPropertyInputSourceID)
        }

        let currentIndex = currentID.flatMap { id in
            sources.firstIndex { $0.id == id }
        }
        let nextIndex = ((currentIndex ?? -1) + 1) % sources.count
        return TISSelectInputSource(sources[nextIndex].inputSource) == noErr
    }

    private func enabledKeyboardSourcesInUserOrder() -> [Source] {
        let allSources = TISCreateInputSourceList(nil, false)
            .takeRetainedValue() as NSArray as! [TISInputSource]

        let sources = allSources.compactMap { inputSource -> Source? in
            guard isEnabled(inputSource),
                  property(inputSource, key: kTISPropertyInputSourceCategory)
                    == (kTISCategoryKeyboardInputSource as String),
                  let id = property(inputSource, key: kTISPropertyInputSourceID) else {
                return nil
            }

            return Source(inputSource: inputSource, id: id)
        }

        var byID: [String: Source] = [:]
        for source in sources {
            byID[source.id] = source
        }

        let configuredIDs = configuredInputSourceIDs()
        var usedIDs: Set<String> = []
        var ordered: [Source] = []

        for id in configuredIDs {
            if let source = byID[id], usedIDs.insert(id).inserted {
                ordered.append(source)
            }
        }

        ordered.append(contentsOf: sources.filter {
            usedIDs.insert($0.id).inserted
        })
        return ordered
    }

    private func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func configuredInputSourceIDs() -> [String] {
        guard let entries = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .array(forKey: "AppleEnabledInputSources") as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { $0["InputSourceID"] as? String }
    }

    private func isEnabled(_ inputSource: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(
            inputSource,
            kTISPropertyInputSourceIsEnabled
        ) else {
            return false
        }

        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }

    private func property(
        _ inputSource: TISInputSource,
        key: CFString
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(inputSource, key) else {
            return nil
        }

        return Unmanaged<CFString>.fromOpaque(pointer)
            .takeUnretainedValue() as String
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

    // This key is an undocumented macOS preference; missing means unknown,
    // not "off". The UI never changes the user's global keyboard settings.
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

    func stop() {
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

        do {
            try remapper.restoreIfOwned()
        } catch {
            lastError = "Cannot restore Caps remap: \(error.localizedDescription)"
        }
        onStateChanged?()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else {
            return
        }

        isPaused = paused
        if paused {
            stop()
        } else {
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
