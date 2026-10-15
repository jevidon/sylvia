import Foundation

/// Offset conversion at the adapter boundary (plan 7.5).
///
/// Sylvia's portable offsets count Unicode scalars in Sylvia-extracted text. WebKit DOM ranges, JavaScript string
/// indices and Readium's JavaScript (`TextRange`, `domRange.offset`) count UTF-16 code units. The two differ by one for
/// every scalar outside the Basic Multilingual Plane (U+10000 and above) that precedes the offset.
public enum TextOffsets {
    /// Converts a Unicode scalar offset into a UTF-16 code-unit offset in `text`. Returns nil when out of range.
    public static func utf16Offset(fromScalarOffset scalarOffset: Int, in text: String) -> Int? {
        guard scalarOffset >= 0 else { return nil }
        var utf16 = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            if scalars == scalarOffset { return utf16 }
            utf16 += scalar.utf16.count
            scalars += 1
        }
        return scalars == scalarOffset ? utf16 : nil
    }

    /// Converts a UTF-16 code-unit offset into a Unicode scalar offset. Returns nil when out of range or when the
    /// offset falls between the two halves of a surrogate pair (an invalid boundary for a quotation).
    public static func scalarOffset(fromUTF16Offset utf16Offset: Int, in text: String) -> Int? {
        guard utf16Offset >= 0 else { return nil }
        var utf16 = 0
        var scalars = 0
        for scalar in text.unicodeScalars {
            if utf16 == utf16Offset { return scalars }
            if utf16 > utf16Offset { return nil }
            utf16 += scalar.utf16.count
            scalars += 1
        }
        return utf16 == utf16Offset ? scalars : nil
    }

    public static func utf16Range(fromScalarRange range: Range<Int>, in text: String) -> Range<Int>? {
        guard let lower = utf16Offset(fromScalarOffset: range.lowerBound, in: text),
              let upper = utf16Offset(fromScalarOffset: range.upperBound, in: text) else { return nil }
        return lower ..< upper
    }

    public static func scalarRange(fromUTF16Range range: Range<Int>, in text: String) -> Range<Int>? {
        guard let lower = scalarOffset(fromUTF16Offset: range.lowerBound, in: text),
              let upper = scalarOffset(fromUTF16Offset: range.upperBound, in: text) else { return nil }
        return lower ..< upper
    }

    /// Scalar offsets of a Swift string range.
    public static func scalarRange(of range: Range<String.Index>, in text: String) -> Range<Int> {
        let lower = text.unicodeScalars.distance(from: text.unicodeScalars.startIndex, to: range.lowerBound)
        let upper = lower + text.unicodeScalars.distance(from: range.lowerBound, to: range.upperBound)
        return lower ..< upper
    }

    /// Substring for a scalar range.
    public static func substring(_ text: String, scalarRange range: Range<Int>) -> String? {
        let scalars = text.unicodeScalars
        guard range.lowerBound >= 0, range.upperBound <= scalars.count else { return nil }
        let lower = scalars.index(scalars.startIndex, offsetBy: range.lowerBound)
        let upper = scalars.index(lower, offsetBy: range.count)
        return String(scalars[lower ..< upper])
    }
}
