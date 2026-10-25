import XCTest
@testable import CapswitchCore

final class LaunchArgumentsTests: XCTestCase {
    func testDefaultStartsApplication() {
        XCTAssertEqual(LaunchArguments(arguments: []), .application)
        XCTAssertEqual(LaunchArguments(arguments: ["--unknown"]), .application)
    }

    func testDoctorAndInstallerDoNotStartGUI() {
        XCTAssertEqual(LaunchArguments(arguments: ["--doctor"]), .doctor)
        XCTAssertEqual(LaunchArguments(arguments: ["--install"]), .install)
    }

    func testRelaunchWaitRequiresPositiveParentPID() {
        XCTAssertEqual(LaunchArguments(arguments: ["--wait-for-pid=4321"]), .waitForParent(4321))
        XCTAssertEqual(LaunchArguments(arguments: ["--wait-for-pid=-1"]), .application)
        XCTAssertEqual(LaunchArguments(arguments: ["--wait-for-pid=0"]), .application)
        XCTAssertEqual(LaunchArguments(arguments: ["--wait-for-pid=foo"]), .application)
    }
}
