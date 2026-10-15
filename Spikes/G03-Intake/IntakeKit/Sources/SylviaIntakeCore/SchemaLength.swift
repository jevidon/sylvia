import Foundation

/// JSON Schema's `minLength` and `maxLength` count Unicode code points (the contract validator counts Python `str`
/// length), not UTF-8 bytes and not Swift `Character`s (grapheme clusters). The manifest readers check their schemas'
/// string bounds with this, so reader and schema agree on every string field (G0.3 review R2-04). Paths and file
/// names are the exception: they are bounded in UTF-8 bytes because the file system is (PATH_MAX, NAME_MAX), which a
/// schema cannot express; each contract states that rule in its description.
public func hasSchemaLength(_ string: String, _ range: ClosedRange<Int>) -> Bool {
    range.contains(string.unicodeScalars.count)
}
