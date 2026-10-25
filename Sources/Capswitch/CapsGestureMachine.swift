public enum GestureEvent: Equatable {
    case capsDown(optionDown: Bool)
    case capsUp(optionDown: Bool)
    case optionDown
    case optionUp
    case reset
}

public enum GestureAction: Equatable {
    case none
    case switchToNextInputSource
    case toggleCapsLock
}

public struct CapsGestureMachine {
    private var capsHeld = false
    private var optionDown = false
    private var optionSeen = false
    private var pendingCapsToggle = false

    public init() {}

    public mutating func handle(_ event: GestureEvent) -> GestureAction {
        switch event {
        case let .capsDown(optionDown):
            guard !capsHeld else {
                return .none
            }

            capsHeld = true
            self.optionDown = optionDown
            optionSeen = optionDown
            return .none

        case let .capsUp(optionDown):
            guard capsHeld else {
                return .none
            }

            capsHeld = false
            self.optionDown = optionDown

            guard optionSeen else {
                return .switchToNextInputSource
            }

            guard !optionDown else {
                pendingCapsToggle = true
                return .none
            }

            return completeCapsToggle()

        case .optionDown:
            optionDown = true
            if capsHeld {
                optionSeen = true
            }
            return .none

        case .optionUp:
            optionDown = false
            guard pendingCapsToggle else {
                return .none
            }

            return completeCapsToggle()

        case .reset:
            capsHeld = false
            optionDown = false
            optionSeen = false
            pendingCapsToggle = false
            return .none
        }
    }

    private mutating func completeCapsToggle() -> GestureAction {
        pendingCapsToggle = false
        optionSeen = false
        return .toggleCapsLock
    }
}
