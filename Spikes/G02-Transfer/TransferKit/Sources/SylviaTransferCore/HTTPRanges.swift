import Foundation

/// Strong entity tags (RFC 9110 section 8.8.3). Sylvia's are `"sha256-<hex>"`, but clients treat
/// them as opaque strong tags and compare byte for byte.
public enum ETag {
    /// A quoted strong tag of 1...128 visible ASCII characters other than `"` and `,`.
    public static func isStrong(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard bytes.count >= 3, bytes.count <= 130, bytes.first == 0x22, bytes.last == 0x22 else { return false }
        return bytes.dropFirst().dropLast().allSatisfy { $0 == 0x21 || (0x23...0x2B).contains($0) || (0x2D...0x7E).contains($0) }
    }

    public static func forContentDigest(_ sha256Hex: String) -> String { "\"sha256-\(sha256Hex)\"" }

    /// Strong comparison: both strong and byte-identical.
    public static func strongMatch(_ lhs: String, _ rhs: String) -> Bool {
        isStrong(lhs) && isStrong(rhs) && lhs == rhs
    }
}

/// A parsed `Range` request header. Only a single `bytes` range is part of the protocol.
public enum RangeRequest: Equatable, Sendable {
    /// `bytes=first-last` or `bytes=first-`.
    case fromTo(first: Int64, last: Int64?)
    /// `bytes=-suffixLength`.
    case suffix(Int64)
    /// More than one range: the protocol rejects it (400 `multiple_ranges_unsupported`).
    case multiple
    /// Syntactically invalid: the protocol rejects it (400 `invalid_range`).
    case invalid

    public static func parse(_ header: String) -> RangeRequest {
        guard header.hasPrefix("bytes=") else { return .invalid }
        let spec = header.dropFirst("bytes=".count)
        if spec.contains(",") { return .multiple }
        guard let dash = spec.firstIndex(of: "-") else { return .invalid }
        let firstText = spec[spec.startIndex..<dash]
        let lastText = spec[spec.index(after: dash)...]
        if firstText.isEmpty {
            guard let suffix = parseDigits(lastText), suffix > 0 else { return .invalid }
            return .suffix(suffix)
        }
        guard let first = parseDigits(firstText) else { return .invalid }
        if lastText.isEmpty { return .fromTo(first: first, last: nil) }
        guard let last = parseDigits(lastText), last >= first else { return .invalid }
        return .fromTo(first: first, last: last)
    }

    /// Resolves against the representation length (RFC 9110 section 14.1.2). Returns nil when unsatisfiable.
    public func resolve(length: Int64) -> ClosedRange<Int64>? {
        guard length > 0 else { return nil }
        switch self {
        case .fromTo(let first, let last):
            guard first < length else { return nil }
            return first...min(last ?? (length - 1), length - 1)
        case .suffix(let count):
            return max(0, length - count)...(length - 1)
        case .multiple, .invalid:
            return nil
        }
    }

    private static func parseDigits(_ text: Substring) -> Int64? {
        guard !text.isEmpty, text.utf8.count <= 19, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return Int64(text)
    }
}

/// `Content-Range` (RFC 9110 section 14.4).
public enum ContentRange {
    public static func satisfied(_ range: ClosedRange<Int64>, length: Int64) -> String {
        "bytes \(range.lowerBound)-\(range.upperBound)/\(length)"
    }

    public static func unsatisfied(length: Int64) -> String { "bytes */\(length)" }

    /// Parses `bytes first-last/complete`. An unknown length (`*`) is not accepted.
    public static func parse(_ value: String) -> (range: ClosedRange<Int64>, length: Int64)? {
        guard value.hasPrefix("bytes ") else { return nil }
        let rest = value.dropFirst("bytes ".count)
        let halves = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        let bounds = halves[0].split(separator: "-", omittingEmptySubsequences: false)
        guard bounds.count == 2, let first = digits(bounds[0]), let last = digits(bounds[1]),
            let length = digits(halves[1]), first <= last, last < length
        else { return nil }
        return (first...last, length)
    }

    private static func digits(_ text: Substring) -> Int64? {
        guard !text.isEmpty, text.utf8.count <= 19, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else {
            return nil
        }
        return Int64(text)
    }
}
