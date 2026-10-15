import Foundation

/// Reads the package String Catalog (`Vocabulary.xcstrings`).
enum VocabularyCatalog {
    static func format(_ key: String) -> String {
        let missing = "\u{1}missing\u{1}"
        let value = Bundle.module.localizedString(forKey: key, value: missing, table: StringCatalog.tableName)
        precondition(value != missing, "vocabulary key \(key) missing from the String Catalog")
        return value
    }

    static func render(_ key: String, arguments: [FormatArgument], locale: Locale) -> String {
        let format = format(key)
        guard !arguments.isEmpty else { return format }
        let cArguments: [any CVarArg] = arguments.map {
            switch $0 {
            case .string(let s): s as NSString
            case .integer(let i): i
            }
        }
        return String(format: format, locale: locale, arguments: cArguments)
    }
}

extension Status {
    /// The phrase from the String Catalog, with arguments formatted for `locale` and `timeZone`.
    /// This is the only way product UI obtains a status string (T54).
    public func text(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        VocabularyCatalog.render(key.rawValue, arguments: arguments(locale: locale, timeZone: timeZone), locale: locale)
    }
}

extension LabelKey {
    /// The label from the String Catalog.
    public var localized: String { VocabularyCatalog.format(rawValue) }
}

extension Marker {
    /// The marker's label for a capture `kind` resolution: the raw kind for an unrecognized kind,
    /// or "Unknown kind" when that raw kind is empty or only white space, so a Pending marker
    /// always carries a visible and spoken label (Sections 4.4.2 and A.1).
    public static func label(for resolution: MarkerResolution) -> String {
        guard let kind = resolution.unrecognizedKind else { return resolution.marker.labelKey.localized }
        return kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? LabelKey.markerUnknownKind.localized : kind
    }
}

/// Durations in the vocabulary's format ("20h 58m", "20h 58m left").
public enum Durations {
    public static func text(seconds: Int, locale: Locale = .current) -> String {
        let (key, values) = DurationText.components(seconds: seconds)
        return VocabularyCatalog.render(key.rawValue, arguments: values.map { .integer($0) }, locale: locale)
    }

    public static func left(seconds: Int, locale: Locale = .current) -> String {
        VocabularyCatalog.render(FormatKey.timeLeft.rawValue,
                                 arguments: [.string(text(seconds: seconds, locale: locale))], locale: locale)
    }
}
