import XCTest
@testable import CapswitchCore

final class CapsGestureMachineTests: XCTestCase {
    func testPlainCapsSwitchesOnlyOnRelease() {
        var machine = CapsGestureMachine()

        XCTAssertEqual(machine.handle(.capsDown(optionDown: false)), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: false)), .switchToNextInputSource)
    }

    func testOptionBeforeCapsTogglesRealCapsLock() {
        var machine = CapsGestureMachine()

        XCTAssertEqual(machine.handle(.optionDown), .none)
        XCTAssertEqual(machine.handle(.capsDown(optionDown: true)), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: true)), .toggleCapsLock)
        XCTAssertEqual(machine.handle(.optionUp), .none)
    }

    func testCapsBeforeOptionTogglesRealCapsLock() {
        var machine = CapsGestureMachine()

        XCTAssertEqual(machine.handle(.capsDown(optionDown: false)), .none)
        XCTAssertEqual(machine.handle(.optionDown), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: true)), .toggleCapsLock)
        XCTAssertEqual(machine.handle(.optionUp), .none)
    }

    func testOptionReleasedAfterCapsCompletesPendingToggle() {
        var machine = CapsGestureMachine()

        XCTAssertEqual(machine.handle(.optionDown), .none)
        XCTAssertEqual(machine.handle(.capsDown(optionDown: true)), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: true)), .none)
        XCTAssertEqual(machine.handle(.optionUp), .toggleCapsLock)
    }

    func testResetCancelsPendingToggle() {
        var machine = CapsGestureMachine()

        XCTAssertEqual(machine.handle(.capsDown(optionDown: false)), .none)
        XCTAssertEqual(machine.handle(.optionDown), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: true)), .none)
        XCTAssertEqual(machine.handle(.reset), .none)
        XCTAssertEqual(machine.handle(.optionUp), .none)

        XCTAssertEqual(machine.handle(.capsDown(optionDown: false)), .none)
        XCTAssertEqual(machine.handle(.capsUp(optionDown: false)), .switchToNextInputSource)
    }
}
