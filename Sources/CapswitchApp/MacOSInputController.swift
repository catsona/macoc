import AppKit
import CapswitchCore
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

enum InputControllerError: LocalizedError {
    case accessibilityRequired
    case eventTapUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityRequired:
            return "Accessibility permission is required to intercept Caps Lock."
        case .eventTapUnavailable:
            return "macOS did not allow the global keyboard event tap to start."
        }
    }
}

final class InputSourceManager {
    private struct Source {
        let inputSource: TISInputSource
        let id: String
    }

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

    @discardableResult
    func selectNextInputSource() -> Bool {
        let sources = enabledKeyboardSourcesInUserOrder()
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

        let byID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let configuredIDs = configuredInputSourceIDs()
        var ordered = configuredIDs.compactMap { byID[$0] }
        let configuredSet = Set(configuredIDs)
        ordered.append(contentsOf: sources.filter { !configuredSet.contains($0.id) })
        return ordered
    }

    private func currentSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func configuredInputSourceIDs() -> [String] {
        guard let entries = UserDefaults.standard.array(
            forKey: "AppleEnabledInputSources"
        ) as? [[String: Any]] else {
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
    private static let capsLockKeyCode: CGKeyCode = 57
    private static let syntheticEventMarker: Int64 = 0x4361707353776974

    private let inputSources = InputSourceManager()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var gestureMachine = CapsGestureMachine()
    private var alphaShiftDown = false
    private var optionDown = false
    private var isPostingSyntheticCaps = false

    var isPaused = false

    var isRunning: Bool {
        eventTap != nil
    }
    var onStateChanged: (() -> Void)?

    var currentInputSourceName: String {
        inputSources.currentDisplayName
    }

    var currentInputSourceShortName: String {
        inputSources.currentShortName
    }

    var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    func start() throws {
        guard eventTap == nil else {
            return
        }

        guard AXIsProcessTrusted() else {
            throw InputControllerError.accessibilityRequired
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            throw InputControllerError.eventTapUnavailable
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
        onStateChanged?()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        resetGestureState()
        onStateChanged?()
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
        if event.getIntegerValueField(.eventSourceUserData)
            == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGestureState()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let newAlphaShiftDown = flags.contains(.maskAlphaShift)
        let newOptionDown = flags.contains(.maskAlternate)
        let isCapsEvent = event.getIntegerValueField(.keyboardEventKeycode)
            == Int64(Self.capsLockKeyCode)

        if isPaused {
            if isCapsEvent {
                alphaShiftDown = newAlphaShiftDown
            }
            optionDown = newOptionDown
            return Unmanaged.passUnretained(event)
        }

        // Alpha-shift is also used by other keyboard events. Use the physical
        // key code so a fast sequence of unrelated flagsChanged events cannot
        // be mistaken for a Caps Lock edge.
        let capsDown = isCapsEvent && newAlphaShiftDown && !alphaShiftDown
        let capsUp = isCapsEvent && !newAlphaShiftDown && alphaShiftDown
        let optionPressed = newOptionDown && !optionDown
        let optionReleased = !newOptionDown && optionDown

        var action: GestureAction = .none

        if optionPressed {
            action = combine(action, gestureMachine.handle(.optionDown))
        }

        if capsDown {
            action = combine(
                action,
                gestureMachine.handle(.capsDown(optionDown: newOptionDown))
            )
        }

        if capsUp {
            action = combine(
                action,
                gestureMachine.handle(.capsUp(optionDown: newOptionDown))
            )
        }

        if optionReleased {
            action = combine(action, gestureMachine.handle(.optionUp))
        }

        if isCapsEvent {
            alphaShiftDown = newAlphaShiftDown
        }
        optionDown = newOptionDown
        apply(action)

        if capsDown || capsUp {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func apply(_ action: GestureAction) {
        switch action {
        case .none:
            break
        case .switchToNextInputSource:
            // TISSelectInputSource can synchronously trigger more keyboard
            // notifications. Let the event tap return first so a rapid key +
            // Caps sequence sees the new source before the next key is typed.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, !self.isPaused else {
                    return
                }
                if self.inputSources.selectNextInputSource() {
                    self.onStateChanged?()
                }
            }
        case .toggleCapsLock:
            postSyntheticCapsLock()
        }
    }

    private func postSyntheticCapsLock() {
        guard !isPostingSyntheticCaps,
              let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.capsLockKeyCode,
                keyDown: true
              ),
              let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: Self.capsLockKeyCode,
                keyDown: false
              ) else {
            return
        }

        isPostingSyntheticCaps = true
        for event in [down, up] {
            event.flags = []
            event.setIntegerValueField(
                .eventSourceUserData,
                value: Self.syntheticEventMarker
            )
            event.post(tap: .cghidEventTap)
        }
        isPostingSyntheticCaps = false
    }

    private func resetGestureState() {
        _ = gestureMachine.handle(.reset)
        alphaShiftDown = false
        optionDown = false
        isPostingSyntheticCaps = false
    }

    private func combine(
        _ first: GestureAction,
        _ second: GestureAction
    ) -> GestureAction {
        first == .none ? second : first
    }
}
