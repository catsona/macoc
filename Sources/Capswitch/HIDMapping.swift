import Foundation

public struct HIDKeyMapping: Equatable, Hashable {
    public let source: UInt64
    public let destination: UInt64

    public init(source: UInt64, destination: UInt64) {
        self.source = source
        self.destination = destination
    }
}

public enum HIDMappingCodecError: Error, Equatable {
    case unrecognizedOutput
    case invalidEntry
}

// Parse OpenStep-style hidutil --get output. Unknown entries are rejected
// rather than risking deletion of someone else's keyboard remappings.
public enum HIDMappingCodec {
    public static let capsUsage: UInt64 = 0x700000039
    public static let f19Usage: UInt64 = 0x70000006E
    public static let capsToF19 = HIDKeyMapping(
        source: capsUsage,
        destination: f19Usage
    )

    public static func parse(_ output: String) throws -> [HIDKeyMapping] {
        var value = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if value.hasPrefix("UserKeyMapping:") {
            value = String(value.dropFirst("UserKeyMapping:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard value.first == "(", value.last == ")" else {
            throw HIDMappingCodecError.unrecognizedOutput
        }

        let inner = String(value.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if inner.isEmpty || inner == "null" {
            return []
        }

        let entryPattern = try NSRegularExpression(pattern: #"\{([^{}]*)\}"#)
        let matches = entryPattern.matches(
            in: inner,
            range: NSRange(inner.startIndex..<inner.endIndex, in: inner)
        )

        guard !matches.isEmpty else {
            throw HIDMappingCodecError.unrecognizedOutput
        }

        let remainder = NSMutableString(string: inner)
        var mappings: [HIDKeyMapping] = []

        for match in matches.reversed() {
            guard let bodyRange = Range(match.range(at: 1), in: inner) else {
                throw HIDMappingCodecError.invalidEntry
            }
            mappings.insert(try parseEntry(String(inner[bodyRange])), at: 0)
            remainder.deleteCharacters(in: match.range)
        }

        let separators = (remainder as String).replacingOccurrences(
            of: #"[\s,]"#,
            with: "",
            options: .regularExpression
        )
        guard separators.isEmpty else {
            throw HIDMappingCodecError.unrecognizedOutput
        }

        return mappings
    }

    public static func setArgument(_ mappings: [HIDKeyMapping]) throws -> String {
        let entries: [[String: NSNumber]] = mappings.map {
            [
                "HIDKeyboardModifierMappingSrc": NSNumber(value: $0.source),
                "HIDKeyboardModifierMappingDst": NSNumber(value: $0.destination),
            ]
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["UserKeyMapping": entries],
            options: [.sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private static func parseEntry(_ body: String) throws -> HIDKeyMapping {
        let fieldPattern = try NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9_]*)\s*=\s*([^;]+);"#
        )
        let matches = fieldPattern.matches(
            in: body,
            range: NSRange(body.startIndex..<body.endIndex, in: body)
        )

        guard matches.count == 2 else {
            throw HIDMappingCodecError.invalidEntry
        }

        let remainder = NSMutableString(string: body)
        var fields: [String: UInt64] = [:]

        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: body),
                  let valueRange = Range(match.range(at: 2), in: body) else {
                throw HIDMappingCodecError.invalidEntry
            }

            let name = String(body[nameRange])
            let literal = body[valueRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let number: UInt64?
            if literal.lowercased().hasPrefix("0x") {
                number = UInt64(literal.dropFirst(2), radix: 16)
            } else {
                number = UInt64(literal)
            }

            guard let number, fields[name] == nil else {
                throw HIDMappingCodecError.invalidEntry
            }
            fields[name] = number
            remainder.deleteCharacters(in: match.range)
        }

        guard (remainder as String)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              fields.count == 2,
              let source = fields["HIDKeyboardModifierMappingSrc"],
              let destination = fields["HIDKeyboardModifierMappingDst"] else {
            throw HIDMappingCodecError.invalidEntry
        }

        return HIDKeyMapping(source: source, destination: destination)
    }
}
