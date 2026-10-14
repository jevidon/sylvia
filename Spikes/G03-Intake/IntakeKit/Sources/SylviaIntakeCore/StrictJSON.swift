import Foundation

/// The JSON text rules the manifest readers apply before decoding (G0.3 review R3-01).
///
/// JSONDecoder (Foundation on macOS 26.6 and the iOS 26.5 simulator) accepts texts that are not JSON and texts the
/// contract validator refuses, and it reads an ambiguous text differently from the validator (`Scripts/validate-contracts.py`
/// reads a file as UTF-8 and parses it with Python's `json.loads`). Measured in
/// `Spikes/G03-Intake/scripts/contract_differential.py`:
/// - it accepts a trailing comma in an object or array, a UTF-8 byte order mark, and UTF-16 and UTF-32 texts, all of
///   which the validator refuses;
/// - it does not look inside members it does not decode, so invalid UTF-8, unescaped control characters, bad escapes,
///   unpaired surrogates and malformed numbers pass there;
/// - for a member name that appears twice it keeps the first value, where the validator keeps the last.
///
/// The readers therefore check the whole text first and accept only strict JSON (RFC 8259) in UTF-8 without a byte
/// order mark, within these limits, which RFC 8259 leaves to implementations (sections 4, 6, 8.2 and 9) and I-JSON
/// (RFC 7493) also sets:
/// - no member name twice in one object, compared after escapes are processed, code point by code point (as I-JSON
///   defines a duplicate and as Python compares keys);
/// - no unpaired surrogate escape (`\ud800` alone): it encodes no character, and UTF-8 cannot hold it;
/// - at most 512 levels of nested objects and arrays, JSONDecoder's own limit;
/// - integers (numbers without a fraction or exponent) of at most 4,300 digits, the validator's own limit (Python's
///   default `int_max_str_digits`; above it `json.loads` fails), so no text a reader accepts is one the validator
///   cannot load.
/// `NaN`, `Infinity` and `-Infinity` are not JSON and are refused (Python's `json` accepts them).
public enum StrictJSON {
    public static let maxDepth = 512
    public static let maxIntegerDigits = 4300

    public struct Violation: Error, Equatable, Sendable, CustomStringConvertible {
        public enum Kind: String, Sendable, CaseIterable {
            case byteOrderMark = "byte_order_mark"
            case invalidUTF8 = "invalid_utf8"
            case syntax = "not_json"
            case nonStandardNumber = "nan_or_infinity"
            case duplicateName = "duplicate_member_name"
            case unpairedSurrogate = "unpaired_surrogate"
            case tooDeep = "nested_too_deep"
            case integerTooLong = "integer_too_long"
        }

        public let kind: Kind
        /// Byte offset in the text where the problem was found.
        public let offset: Int

        public init(_ kind: Kind, at offset: Int) {
            self.kind = kind
            self.offset = offset
        }

        public var description: String { "\(kind.rawValue) at byte \(offset)" }
    }

    /// Returns when `data` is one strict JSON text within the limits above; otherwise throws the first violation.
    public static func check(_ data: Data) throws(Violation) {
        var scanner = StrictJSONScanner(bytes: [UInt8](data))
        try scanner.scanText()
    }
}

/// One pass over the bytes, without recursion (the nesting limit is enforced, never relied on for the stack).
private struct StrictJSONScanner {
    typealias Violation = StrictJSON.Violation

    let bytes: [UInt8]
    var index = 0
    /// One entry per open container, innermost last: whether it is an object, and the member names it has had so far
    /// (each name as the UTF-8 bytes of its code points; always empty for an array).
    var isObject: [Bool] = []
    var names: [Set<[UInt8]>] = []
    /// The member name being scanned, as the UTF-8 bytes of its code points (escapes processed).
    var collected: [UInt8] = []

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func scanText() throws(Violation) {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            throw Violation(.byteOrderMark, at: 0)
        }
        skipWhitespace()
        var valueFollows = true
        while valueFollows {
            // A value starts here.
            guard index < bytes.count else { throw Violation(.syntax, at: index) }
            switch bytes[index] {
            case 0x7B:   // {
                try openContainer(object: true)
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == 0x7D {   // } : an empty object is a complete value
                    index += 1
                    closeContainer()
                } else {
                    try scanMemberName()
                    continue   // the first member's value comes next
                }
            case 0x5B:   // [
                try openContainer(object: false)
                index += 1
                skipWhitespace()
                if index < bytes.count, bytes[index] == 0x5D {   // ] : an empty array is a complete value
                    index += 1
                    closeContainer()
                } else {
                    continue   // the first element comes next
                }
            case 0x22:   // "
                try scanString(collect: false)
            case 0x74:
                try expectLiteral("true")
            case 0x66:
                try expectLiteral("false")
            case 0x6E:
                try expectLiteral("null")
            case 0x2D, 0x30...0x39:   // - 0-9
                try scanNumber()
            default:
                if hasPrefix("NaN") || hasPrefix("Infinity") { throw Violation(.nonStandardNumber, at: index) }
                throw Violation(.syntax, at: index)
            }
            valueFollows = try afterValue()
        }
        skipWhitespace()
        guard index == bytes.count else { throw Violation(.syntax, at: index) }
    }

    /// After a complete value: closes the containers that end here. Returns true when another value follows (after a
    /// comma; in an object, after the next member's name and colon), false when the top-level value is complete.
    mutating func afterValue() throws(Violation) -> Bool {
        while true {
            skipWhitespace()
            guard let object = isObject.last else { return false }
            guard index < bytes.count else { throw Violation(.syntax, at: index) }
            let byte = bytes[index]
            if byte == 0x2C {   // ,
                index += 1
                skipWhitespace()
                // In an object a member name must follow; a trailing comma before } fails here. In an array, a value
                // must follow; a trailing comma before ] fails when the next value is scanned.
                if object { try scanMemberName() }
                return true
            }
            guard byte == (object ? 0x7D : 0x5D) else { throw Violation(.syntax, at: index) }
            index += 1
            closeContainer()
        }
    }

    mutating func scanMemberName() throws(Violation) {
        guard index < bytes.count, bytes[index] == 0x22 else { throw Violation(.syntax, at: index) }
        let start = index
        collected.removeAll(keepingCapacity: true)
        try scanString(collect: true)
        guard names[names.count - 1].insert(collected).inserted else { throw Violation(.duplicateName, at: start) }
        skipWhitespace()
        guard index < bytes.count, bytes[index] == 0x3A else { throw Violation(.syntax, at: index) }   // :
        index += 1
        skipWhitespace()
    }

    mutating func openContainer(object: Bool) throws(Violation) {
        guard isObject.count < StrictJSON.maxDepth else { throw Violation(.tooDeep, at: index) }
        isObject.append(object)
        names.append([])
    }

    mutating func closeContainer() {
        isObject.removeLast()
        names.removeLast()
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    func hasPrefix(_ literal: String) -> Bool {
        let literalBytes = Array(literal.utf8)
        return index + literalBytes.count <= bytes.count && Array(bytes[index..<(index + literalBytes.count)]) == literalBytes
    }

    mutating func expectLiteral(_ literal: String) throws(Violation) {
        guard hasPrefix(literal) else { throw Violation(.syntax, at: index) }
        index += literal.utf8.count
    }

    /// RFC 8259 number: [-] (0 | [1-9][0-9]*) [. [0-9]+] [(e|E) [+|-] [0-9]+]. What follows it is checked by the caller.
    mutating func scanNumber() throws(Violation) {
        let start = index
        if bytes[index] == 0x2D {
            index += 1
            if hasPrefix("Infinity") { throw Violation(.nonStandardNumber, at: start) }
        }
        guard index < bytes.count, isDigit(bytes[index]) else { throw Violation(.syntax, at: index) }
        var digits = 0
        if bytes[index] == 0x30 {
            index += 1
            digits = 1
        } else {
            while index < bytes.count, isDigit(bytes[index]) {
                index += 1
                digits += 1
            }
        }
        var integer = true
        if index < bytes.count, bytes[index] == 0x2E {   // .
            integer = false
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw Violation(.syntax, at: index) }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {   // e E
            integer = false
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { throw Violation(.syntax, at: index) }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if integer, digits > StrictJSON.maxIntegerDigits { throw Violation(.integerTooLong, at: start) }
    }

    func isDigit(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) }

    /// A string from its opening quote to its closing quote. With `collect`, appends the string's code points to
    /// `collected` as UTF-8 (escapes processed), so that member names can be compared exactly.
    mutating func scanString(collect: Bool) throws(Violation) {
        index += 1   // opening quote
        while true {
            guard index < bytes.count else { throw Violation(.syntax, at: index) }   // unterminated
            let byte = bytes[index]
            switch byte {
            case 0x22:
                index += 1
                return
            case 0x5C:
                try scanEscape(collect: collect)
            case 0x00...0x1F:
                throw Violation(.syntax, at: index)   // a control character must be escaped
            case 0x20...0x7F:
                if collect { collected.append(byte) }
                index += 1
            default:
                let length = try utf8SequenceLength(at: index)
                if collect { collected.append(contentsOf: bytes[index..<(index + length)]) }
                index += length
            }
        }
    }

    mutating func scanEscape(collect: Bool) throws(Violation) {
        let start = index
        guard index + 1 < bytes.count else { throw Violation(.syntax, at: start) }
        let simple: UInt8
        switch bytes[index + 1] {
        case 0x22: simple = 0x22   // \"
        case 0x5C: simple = 0x5C   // \\
        case 0x2F: simple = 0x2F   // \/
        case 0x62: simple = 0x08   // \b
        case 0x66: simple = 0x0C   // \f
        case 0x6E: simple = 0x0A   // \n
        case 0x72: simple = 0x0D   // \r
        case 0x74: simple = 0x09   // \t
        case 0x75:                 // \uXXXX
            guard let unit = hex4(at: index + 2) else { throw Violation(.syntax, at: start) }
            index += 6
            var scalar = unit
            if (0xD800...0xDBFF).contains(unit) {
                // A high surrogate must be followed at once by an escaped low surrogate; together they are one code point.
                guard index + 1 < bytes.count, bytes[index] == 0x5C, bytes[index + 1] == 0x75,
                      let low = hex4(at: index + 2), (0xDC00...0xDFFF).contains(low) else {
                    throw Violation(.unpairedSurrogate, at: start)
                }
                index += 6
                scalar = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
            } else if (0xDC00...0xDFFF).contains(unit) {
                throw Violation(.unpairedSurrogate, at: start)
            }
            if collect, let codePoint = Unicode.Scalar(scalar) { collected.append(contentsOf: codePoint.utf8) }
            return
        default:
            throw Violation(.syntax, at: start)
        }
        if collect { collected.append(simple) }
        index += 2
    }

    func hex4(at position: Int) -> UInt32? {
        guard position + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for byte in bytes[position..<(position + 4)] {
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            default: return nil
            }
            value = value << 4 | digit
        }
        return value
    }

    /// Length of the well-formed UTF-8 sequence that starts at `position` with a byte above 0x7F (Unicode Table 3-7:
    /// no overlong forms, no encoded surrogates, nothing above U+10FFFF), as Python's strict UTF-8 decoder requires.
    func utf8SequenceLength(at position: Int) throws(Violation) -> Int {
        let length: Int
        var second: ClosedRange<UInt8> = 0x80...0xBF
        switch bytes[position] {
        case 0xC2...0xDF: length = 2
        case 0xE0: length = 3; second = 0xA0...0xBF
        case 0xE1...0xEC, 0xEE...0xEF: length = 3
        case 0xED: length = 3; second = 0x80...0x9F
        case 0xF0: length = 4; second = 0x90...0xBF
        case 0xF1...0xF3: length = 4
        case 0xF4: length = 4; second = 0x80...0x8F
        default: throw Violation(.invalidUTF8, at: position)
        }
        guard position + length <= bytes.count, second.contains(bytes[position + 1]) else {
            throw Violation(.invalidUTF8, at: position)
        }
        for offset in 2..<length where !(0x80...0xBF).contains(bytes[position + offset]) {
            throw Violation(.invalidUTF8, at: position)
        }
        return length
    }
}
