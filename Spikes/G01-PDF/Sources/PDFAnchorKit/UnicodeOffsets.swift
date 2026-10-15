import Foundation

/// A half-open range of Unicode scalar offsets into a page's extracted text (plan 7.5: Sylvia-extracted
/// text uses Unicode scalar offsets; native UTF-16 ranges are converted at the adapter boundary).
public struct ScalarRange: Codable, Hashable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public var length: Int { end - start }
}

public enum OffsetConversionError: Error, Equatable, Sendable {
    /// The range lies outside the text.
    case outOfBounds
    /// A range boundary falls between the two UTF-16 code units of one scalar (a surrogate pair).
    case splitsSurrogatePair
}

/// Conversion between PDFKit's UTF-16 `NSRange`s and Unicode scalar offsets.
///
/// Both directions are exact: no normalization, no grapheme snapping. A combining mark is its own scalar,
/// so a range may legitimately start or end inside a grapheme cluster; that is preserved, not "fixed".
public enum UnicodeOffsets {
    public static func scalarRange(fromUTF16 range: NSRange, in text: String) throws(OffsetConversionError) -> ScalarRange {
        guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else {
            throw .outOfBounds
        }
        let lower = range.location
        let upper = range.location + range.length
        var utf16Offset = 0
        var scalarOffset = 0
        var start: Int?
        var end: Int?
        for scalar in text.unicodeScalars {
            if utf16Offset == lower { start = scalarOffset }
            if utf16Offset == upper { end = scalarOffset }
            let width = scalar.utf16.count
            if (lower > utf16Offset && lower < utf16Offset + width) || (upper > utf16Offset && upper < utf16Offset + width) {
                throw .splitsSurrogatePair
            }
            utf16Offset += width
            scalarOffset += 1
        }
        if utf16Offset == lower { start = scalarOffset }
        if utf16Offset == upper { end = scalarOffset }
        guard let s = start, let e = end else { throw .outOfBounds }
        return ScalarRange(start: s, end: e)
    }

    public static func utf16Range(fromScalar range: ScalarRange, in text: String) throws(OffsetConversionError) -> NSRange {
        guard range.start >= 0, range.end >= range.start else { throw .outOfBounds }
        var utf16Offset = 0
        var scalarOffset = 0
        var start: Int?
        var end: Int?
        for scalar in text.unicodeScalars {
            if scalarOffset == range.start { start = utf16Offset }
            if scalarOffset == range.end { end = utf16Offset }
            utf16Offset += scalar.utf16.count
            scalarOffset += 1
        }
        if scalarOffset == range.start { start = utf16Offset }
        if scalarOffset == range.end { end = utf16Offset }
        guard let s = start, let e = end else { throw .outOfBounds }
        return NSRange(location: s, length: e - s)
    }

    /// The scalars of `text` in `range`, as a String (no normalization).
    public static func substring(_ text: String, scalars range: ScalarRange) throws(OffsetConversionError) -> String {
        let scalars = Array(text.unicodeScalars)
        guard range.start >= 0, range.end <= scalars.count, range.start <= range.end else {
            throw .outOfBounds
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range.start..<range.end])
        return String(view)
    }

    /// Scalar-exact equality. Swift's `==` on String uses canonical equivalence ("é" == "e\u{301}"),
    /// which is wrong for quotation fidelity (plan I-05), so anchors compare scalars.
    public static func scalarsEqual(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.elementsEqual(b.unicodeScalars)
    }

    public static func scalarCount(_ text: String) -> Int {
        text.unicodeScalars.count
    }
}
