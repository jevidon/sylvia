import Foundation

/// UTC wall-clock source in integer milliseconds since the Unix epoch (plan 7.2: 64-bit
/// timestamps). Injectable so tests and the golden corpus are deterministic.
public struct UTCClock: Sendable {
    public let nowMillis: @Sendable () -> Int64

    public init(nowMillis: @escaping @Sendable () -> Int64) {
        self.nowMillis = nowMillis
    }

    public static let system = UTCClock { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    /// A clock that starts at `start` and advances one millisecond per reading.
    public static func stepping(from start: Int64) -> UTCClock {
        let counter = Counter(start)
        return UTCClock { counter.next() }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64
        init(_ value: Int64) { self.value = value }
        func next() -> Int64 { lock.withLock { defer { value += 1 }; return value } }
    }
}

/// Locally generated identifiers (plan 7.3): lowercase UUID strings.
public enum EntityID {
    public static func make() -> String { UUID().uuidString.lowercased() }

    public static func isValid(_ value: String) -> Bool {
        guard value.count == 36, value == value.lowercased() else { return false }
        return UUID(uuidString: value) != nil
    }
}

/// A user-effective date with its precision (plan 7.3, 12): "read it in 2019" is stored as
/// `2019` / `year`, never padded into a fake day. Stored separately from UTC event timestamps.
public struct EffectiveDate: Sendable, Hashable, Codable {
    public enum Precision: String, Sendable, Codable, CaseIterable {
        case year, month, day
    }

    public let value: String
    public let precision: Precision

    public init(_ value: String, precision: Precision) throws {
        guard EffectiveDate.isValid(value, precision: precision) else {
            throw ValidationError.invalidEffectiveDate(value, precision.rawValue)
        }
        self.value = value
        self.precision = precision
    }

    public static func year(_ y: Int) throws -> EffectiveDate {
        try EffectiveDate(String(format: "%04d", y), precision: .year)
    }

    public static func month(_ y: Int, _ m: Int) throws -> EffectiveDate {
        try EffectiveDate(String(format: "%04d-%02d", y, m), precision: .month)
    }

    public static func day(_ y: Int, _ m: Int, _ d: Int) throws -> EffectiveDate {
        try EffectiveDate(String(format: "%04d-%02d-%02d", y, m, d), precision: .day)
    }

    static func isValid(_ value: String, precision: Precision) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        let expected: Int
        switch precision {
        case .year: expected = 1
        case .month: expected = 2
        case .day: expected = 3
        }
        guard parts.count == expected else { return false }
        let widths = [4, 2, 2]
        var numbers: [Int] = []
        for (index, part) in parts.enumerated() {
            guard part.count == widths[index], part.allSatisfy(\.isASCII), let n = Int(part) else { return false }
            numbers.append(n)
        }
        if numbers.count >= 2, !(1...12).contains(numbers[1]) { return false }
        if numbers.count == 3 {
            var components = DateComponents()
            components.year = numbers[0]; components.month = numbers[1]; components.day = numbers[2]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            guard components.isValidDate(in: calendar) else { return false }
        }
        return true
    }
}

public enum ValidationError: Error, Equatable, CustomStringConvertible {
    case invalidEffectiveDate(String, String)
    case invalidRating(Int)
    case invalidDigest(String)
    case invalidIdentifier(String)
    case emptyCapture

    public var description: String {
        switch self {
        case .invalidEffectiveDate(let v, let p): return "invalid effective date \(v) for precision \(p)"
        case .invalidRating(let v): return "rating \(v) is outside 1-10 (half-stars); use nil to clear"
        case .invalidDigest(let v): return "not a lowercase hex SHA-256 digest: \(v)"
        case .invalidIdentifier(let v): return "not a lowercase UUID: \(v)"
        case .emptyCapture: return "a capture needs at least one anchor"
        }
    }
}
