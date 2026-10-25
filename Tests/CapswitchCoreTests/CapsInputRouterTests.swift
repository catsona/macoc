import XCTest
@testable import CapswitchCore

final class CapsInputRouterTests: XCTestCase {
    func testPhysicalCapsToF19UnderContinuousTyping() {
        var router = CapsInputRouter()

        for _ in 0..<100 {
            XCTAssertEqual(router.keyDown(code: 0, optionDown: false), .none)
            XCTAssertEqual(router.keyDown(code: 80, optionDown: false), .none)
            XCTAssertEqual(router.keyDown(code: 80, optionDown: false, isRepeat: true), .none)
            XCTAssertEqual(router.keyUp(code: 0, optionDown: false), .none)
            XCTAssertEqual(router.keyUp(code: 80, optionDown: false), .switchToNextInputSource)
        }
    }

    func testOptionBeforeF19TogglesOnlyAfterOptionRelease() {
        var router = CapsInputRouter()

        XCTAssertEqual(router.flagsChanged(optionDown: true), .none)
        XCTAssertEqual(router.keyDown(code: 80, optionDown: true), .none)
        XCTAssertEqual(router.keyUp(code: 80, optionDown: true), .none)
        XCTAssertEqual(router.flagsChanged(optionDown: false), .toggleCapsLock)
    }

    func testOptionDuringF19TogglesNotSwitches() {
        var router = CapsInputRouter()

        XCTAssertEqual(router.keyDown(code: 80, optionDown: false), .none)
        XCTAssertEqual(router.flagsChanged(optionDown: true), .none)
        XCTAssertEqual(router.flagsChanged(optionDown: false), .none)
        XCTAssertEqual(router.keyUp(code: 80, optionDown: false), .toggleCapsLock)
    }

    func testOptionReleaseOnNextF19DownKeepsPendingCapsToggle() {
        var router = CapsInputRouter()

        XCTAssertEqual(router.flagsChanged(optionDown: true), .none)
        XCTAssertEqual(router.keyDown(code: 80, optionDown: true), .none)
        XCTAssertEqual(router.keyUp(code: 80, optionDown: true), .none)

        // When the Option-up event is folded into the following key event,
        // complete the previous toggle without losing it.
        XCTAssertEqual(router.keyDown(code: 80, optionDown: false), .toggleCapsLock)
        XCTAssertEqual(router.keyUp(code: 80, optionDown: false), .switchToNextInputSource)
    }

    func testOrphanReleaseAndResetDoNotSwitch() {
        var router = CapsInputRouter()

        XCTAssertEqual(router.keyUp(code: 80, optionDown: false), .none)
        XCTAssertEqual(router.keyDown(code: 80, optionDown: false), .none)
        router.reset()
        XCTAssertEqual(router.keyUp(code: 80, optionDown: false), .none)
    }
}
