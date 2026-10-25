import Foundation
import XCTest
@testable import CapswitchCore

final class HIDMappingCodecTests: XCTestCase {
    func testMissingMappingsReadAsEmpty() throws {
        XCTAssertEqual(try HIDMappingCodec.parse("(null)\n"), [])
        XCTAssertEqual(try HIDMappingCodec.parse("UserKeyMapping:(\n)\n"), [])
    }

    func testReadsDecimalMappingsAndPreservesTheirOrder() throws {
        let output = """
        UserKeyMapping:(
            {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            },
            {
                HIDKeyboardModifierMappingSrc = 30064771129;
                HIDKeyboardModifierMappingDst = 30064771182;
            }
        )
        """
        let mappings = try HIDMappingCodec.parse(output)

        XCTAssertEqual(mappings, [
            HIDKeyMapping(source: 30064771172, destination: 30064771125),
            .init(source: 30064771129, destination: 30064771182),
        ])
        XCTAssertEqual(mappings[1], HIDMappingCodec.capsToF19)
    }

    func testEncodeMappingPreservesOtherEntries() throws {
        let original = [HIDKeyMapping(source: 30064771302, destination: 30064771300)]
        let installed = original + [HIDMappingCodec.capsToF19]
        let remaining = installed.filter { $0 != HIDMappingCodec.capsToF19 }
        XCTAssertEqual(remaining, original)

        let payload = try HIDMappingCodec.setArgument(installed)
        let dictionary = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        )
        let entries = try XCTUnwrap(dictionary["UserKeyMapping"] as? [[String: NSNumber]])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(
            entries[1]["HIDKeyboardModifierMappingDst"]?.uint64Value,
            HIDMappingCodec.f19Usage
        )
    }

    func testUnknownFieldsOrGarbageAreRejected() {
        XCTAssertThrowsError(try HIDMappingCodec.parse("hidutil failed"))
        XCTAssertThrowsError(try HIDMappingCodec.parse("({ Foo = 123; })"))
        XCTAssertThrowsError(try HIDMappingCodec.parse(
            "({ HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; Mystery = 3; })"
        ))
    }
}
