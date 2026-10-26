import XCTest
@testable import CapswitchCore

final class LayoutIndicatorTests: XCTestCase {
    func testUSLayoutsKeepLEDOff() {
        for id in ["com.apple.keylayout.US", "com.apple.keylayout.ABC"] {
            XCTAssertEqual(LayoutIndicator.capsLEDEnabled(inputSourceID: id), false)
        }
    }

    func testOtherLayoutsIncludingEnglishAndInputMethodsLightLED() {
        for id in [
            "com.apple.keylayout.Russian",
            "com.apple.keylayout.British",
            "com.apple.keylayout.USInternational-PC",
            "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
            "org.example.custom-layout",
        ] {
            XCTAssertEqual(LayoutIndicator.capsLEDEnabled(inputSourceID: id), true, id)
        }
    }

    func testUnavailableSourceLeavesLEDUnchanged() {
        XCTAssertNil(LayoutIndicator.capsLEDEnabled(inputSourceID: nil))
        XCTAssertNil(LayoutIndicator.capsLEDEnabled(inputSourceID: ""))
    }
}
