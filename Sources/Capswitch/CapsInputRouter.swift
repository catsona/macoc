// Routes ordinary F19 down/up events (physical Caps after HID remap) and
// Option modifier changes into the pure gesture state machine.
public struct CapsInputRouter {
    public static let f19VirtualKeyCode: UInt16 = 80

    private var machine = CapsGestureMachine()
    private var optionHeld = false

    public init() {}

    public mutating func reset() {
        _ = machine.handle(.reset)
        optionHeld = false
    }

    public mutating func flagsChanged(optionDown: Bool) -> GestureAction {
        updateOptionState(optionDown)
    }

    public mutating func keyDown(
        code: UInt16,
        optionDown: Bool,
        isRepeat: Bool = false
    ) -> GestureAction {
        let modifierAction = updateOptionState(optionDown)
        guard code == Self.f19VirtualKeyCode, !isRepeat else {
            return modifierAction
        }
        let keyAction = machine.handle(.capsDown(optionDown: optionDown))
        return modifierAction == .none ? keyAction : modifierAction
    }

    public mutating func keyUp(
        code: UInt16,
        optionDown: Bool
    ) -> GestureAction {
        let modifierAction = updateOptionState(optionDown)
        guard code == Self.f19VirtualKeyCode else {
            return modifierAction
        }
        let keyAction = machine.handle(.capsUp(optionDown: optionDown))
        return modifierAction == .none ? keyAction : modifierAction
    }

    private mutating func updateOptionState(_ down: Bool) -> GestureAction {
        guard down != optionHeld else {
            return .none
        }

        optionHeld = down
        return machine.handle(down ? .optionDown : .optionUp)
    }
}
