import Foundation

/// Path text tests at the level the file system and the contracts' patterns work at: UTF-8 bytes (equivalently, code
/// points), where every "/" (0x2F) separates two components.
///
/// Swift's `String` compares and searches by `Character` (extended grapheme cluster). A "/" followed by a combining
/// mark such as U+0301, a spacing mark or a zero-width joiner, or preceded by a prepended concatenation mark such as
/// U+0600, forms one `Character` with that mark (Unicode UAX #29, rules GB9, GB9a and GB9b). `split(separator: "/")`,
/// `hasPrefix("/")`, `contains("/")` and `==` then do not see that "/" at all, while `open(2)` and the schema do: the
/// G0.3 readers accepted the manifest path "../" + U+0301 + "x", and extraction wrote that file into the parent of its
/// extraction directory (report finding F18; `host-path-separator-before-fix.log`). Every path rule in G0.3 uses these
/// functions instead. 0x2F never occurs inside a multi-byte UTF-8 sequence, so splitting the bytes there is exact.
public enum PathBytes {
    public static let separator = UInt8(ascii: "/")
    static let dot = UInt8(ascii: ".")

    /// The components between separators, empty ones included, exactly as the file system splits the path.
    public static func components(_ path: String) -> [String] {
        path.utf8.split(separator: separator, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Whether the text holds a "/" anywhere, whatever follows or precedes it.
    public static func containsSeparator(_ text: String) -> Bool {
        text.utf8.contains(separator)
    }

    public static func startsWithSeparator(_ text: String) -> Bool { text.utf8.first == separator }

    public static func endsWithSeparator(_ text: String) -> Bool { text.utf8.last == separator }

    /// "." or "..", byte for byte (".́", a dot carrying a combining mark, is an ordinary name).
    public static func isDotOrDotDot(_ component: String) -> Bool {
        let bytes = Array(component.utf8)
        return bytes == [dot] || bytes == [dot, dot]
    }

    /// Byte-for-byte prefix test (no canonical equivalence, no grapheme clustering).
    public static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// Byte-for-byte suffix test.
    public static func hasSuffix(_ text: String, _ suffix: String) -> Bool {
        text.utf8.reversed().starts(with: suffix.utf8.reversed())
    }

    /// Byte-for-byte equality (Swift's `==` treats canonically equivalent strings as equal).
    public static func equal(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// Whether `url` lies strictly inside `directory`, comparing standardized paths byte for byte. Both are standardized
    /// lexically (".." and "." resolved, no symbolic links followed).
    public static func isInside(_ url: URL, directory: URL) -> Bool {
        let root = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = endsWithSeparator(root) ? root : root + "/"
        return hasPrefix(path, prefix) && path.utf8.count > prefix.utf8.count
    }
}
