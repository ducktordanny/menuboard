import Foundation

/// Parses "3000-3999, 5173 8080" into port ranges. Unparseable tokens are reported, not fatal.
struct PortFilter {
    let ranges: [ClosedRange<UInt16>]
    let invalidTokens: [String]

    init(_ spec: String) {
        var ranges: [ClosedRange<UInt16>] = []
        var invalid: [String] = []
        let tokens = spec.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        for token in tokens {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            let numbers = bounds.compactMap { UInt16($0) }
            switch (bounds.count, numbers.count) {
            case (1, 1):
                ranges.append(numbers[0]...numbers[0])
            case (2, 2):
                ranges.append(min(numbers[0], numbers[1])...max(numbers[0], numbers[1]))
            default:
                invalid.append(String(token))
            }
        }
        self.ranges = ranges
        self.invalidTokens = invalid
    }

    var isEmpty: Bool { ranges.isEmpty }

    func matches(_ port: UInt16) -> Bool {
        ranges.contains { $0.contains(port) }
    }
}
