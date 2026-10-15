import Foundation

/// Kinds of endpoint in the disclosure row (Section 14.2).
public enum EndpointKind: String, CaseIterable, Sendable, Codable {
    case hosted
    case local
    case userManaged = "user_managed"
}

/// A typed status phrase: one case per vocabulary entry, carrying its arguments. Views render a
/// `Status` through the design package (`Status.text(...)` in SylviaDesign) and never spell the
/// phrase themselves (Section 4.4.9, T54).
public enum Status: Sendable, Hashable {
    case saving
    case saved
    /// "Saved" with the time of the durable commit (only after the commit callback; I-03).
    case savedAt(Date)
    case notSaved
    case queued
    case waitingFor(source: String)
    case receiving
    /// "3.1 of 5.2 GB verified". Bytes, 64-bit (Contracts/README.md units).
    case bytesVerified(verified: Int64, total: Int64)
    case verifying
    case preparing
    case needsReview
    case ready
    case readyIndexingContinues
    case needsAttention
    case queuedOnMac
    case downloadedToPhone
    case importedIntoSylvia
    case momentSavedPreservingAudio
    case audioExcerptSaved
    case excerptNotPreserved
    case draftNotSent
    case sendingTo(host: String)
    case generated
    case complete
    case interruptedPartialAnswer
    case scopeSelectedPassage
    case scopePassageAndNearbyText
    case scopeRelevantPassagesFromWork
    case scopeSelectedThoughts
    case relevantPassagesRetrieved
    case onThisDevice
    case notOnThisDevice(source: String)
    case recordOnly
    case savedThoughtsOnly
    case bookTextIndexed
    case indexingChapters(indexed: Int, total: Int)
    case textUnavailable
    case removeDownload
    case manageRetainedText
    case removeExcerptAudio
    case deleteRecordAndThoughts
    case endpoint(host: String, kind: EndpointKind, model: String?)

    public var key: VocabularyKey {
        switch self {
        case .saving: .saveInProgress
        case .saved: .saveDone
        case .savedAt: .saveDoneAt
        case .notSaved: .saveFailed
        case .queued: .importQueued
        case .waitingFor: .importWaitingForSource
        case .receiving: .importReceiving
        case .bytesVerified: .importBytesVerified
        case .verifying: .importVerifying
        case .preparing: .importPreparing
        case .needsReview: .importNeedsReview
        case .ready: .importReady
        case .readyIndexingContinues: .importReadyIndexing
        case .needsAttention: .importNeedsAttention
        case .queuedOnMac: .deliveryQueuedOnMac
        case .downloadedToPhone: .deliveryDownloadedToPhone
        case .importedIntoSylvia: .deliveryImportedIntoSylvia
        case .momentSavedPreservingAudio: .audioMomentSaved
        case .audioExcerptSaved: .audioExcerptSaved
        case .excerptNotPreserved: .audioExcerptNotPreserved
        case .draftNotSent: .askDraftNotSent
        case .sendingTo: .askSending
        case .generated: .askGenerated
        case .complete: .askComplete
        case .interruptedPartialAnswer: .askInterrupted
        case .scopeSelectedPassage: .scopeSelectedPassage
        case .scopePassageAndNearbyText: .scopePassageAndNearby
        case .scopeRelevantPassagesFromWork: .scopeWorkSearch
        case .scopeSelectedThoughts: .scopeSelectedThoughts
        case .relevantPassagesRetrieved: .scopePassagesRetrieved
        case .onThisDevice: .fileOnDevice
        case .notOnThisDevice: .fileNotOnDevice
        case .recordOnly: .fileRecordOnly
        case .savedThoughtsOnly: .searchSavedThoughtsOnly
        case .bookTextIndexed: .searchBookTextIndexed
        case .indexingChapters: .searchIndexing
        case .textUnavailable: .searchTextUnavailable
        case .removeDownload: .removeDownload
        case .manageRetainedText: .removeManageRetainedText
        case .removeExcerptAudio: .removeExcerptAudio
        case .deleteRecordAndThoughts: .removeDeleteRecordAndThoughts
        case .endpoint(_, let kind, let model):
            // An empty model identifier is treated as absent.
            switch (kind, model.map { !$0.isEmpty } ?? false) {
            case (.hosted, false): .endpointHosted
            case (.local, false): .endpointLocal
            case (.userManaged, false): .endpointUserManaged
            case (.hosted, true): .endpointHostedModel
            case (.local, true): .endpointLocalModel
            case (.userManaged, true): .endpointUserManagedModel
            }
        }
    }

    /// The status for a key that takes no arguments, or nil when the key needs arguments.
    public init?(key: VocabularyKey) {
        let all: [Status] = [
            .saving, .saved, .notSaved, .queued, .receiving, .verifying, .preparing, .needsReview, .ready,
            .readyIndexingContinues, .needsAttention, .queuedOnMac, .downloadedToPhone, .importedIntoSylvia,
            .momentSavedPreservingAudio, .audioExcerptSaved, .excerptNotPreserved, .draftNotSent, .generated,
            .complete, .interruptedPartialAnswer, .scopeSelectedPassage, .scopePassageAndNearbyText,
            .scopeRelevantPassagesFromWork, .scopeSelectedThoughts, .relevantPassagesRetrieved, .onThisDevice,
            .recordOnly, .savedThoughtsOnly, .bookTextIndexed, .textUnavailable, .removeDownload,
            .manageRetainedText, .removeExcerptAudio, .deleteRecordAndThoughts,
        ]
        guard let match = all.first(where: { $0.key == key }) else { return nil }
        self = match
    }

    /// Arguments in placeholder order, formatted for `locale` and `timeZone`.
    public func arguments(locale: Locale, timeZone: TimeZone) -> [FormatArgument] {
        switch self {
        case .savedAt(let date):
            return [.string(TimestampText.time(date, locale: locale, timeZone: timeZone))]
        case .waitingFor(let source), .notOnThisDevice(let source):
            return [.string(source)]
        case .bytesVerified(let verified, let total):
            let parts = ByteProgressText.parts(verified: verified, total: total, locale: locale)
            return [.string(parts.verified), .string(parts.total)]
        case .sendingTo(let host):
            return [.string(host)]
        case .endpoint(let host, _, let model):
            if let model, !model.isEmpty { return [.string(host), .string(model)] }
            return [.string(host)]
        case .indexingChapters(let indexed, let total):
            return [.integer(Int64(indexed)), .integer(Int64(total))]
        default:
            return []
        }
    }

    /// English rendering straight from the vocabulary templates. The shipping path is the String
    /// Catalog (`Status.text` in SylviaDesign); tests assert the two agree.
    public func englishText(locale: Locale = Locale(identifier: "en_US_POSIX"),
                            timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> String {
        Template.render(key.text, placeholders: key.placeholders, plural: key.plural,
                        arguments: arguments(locale: locale, timeZone: timeZone), locale: locale)
    }
}

/// A formatted argument for a vocabulary template.
public enum FormatArgument: Sendable, Hashable {
    case string(String)
    case integer(Int64)
}

/// Renders `{placeholder}` templates (used for the English rendering and for the String Catalog
/// format strings).
public enum Template {
    public static func placeholderNames(in text: String) -> [String] {
        var names: [String] = []
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            names.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    public static func render(_ text: String, placeholders: [Placeholder], plural: PluralForms?,
                              arguments: [FormatArgument], locale: Locale) -> String {
        precondition(arguments.count == placeholders.count, "argument count mismatch for \(text)")
        var result = text
        if let plural, let index = placeholders.firstIndex(where: { $0.name == plural.placeholder }),
           case .integer(let count) = arguments[index], count == 1 {
            result = result.replacingOccurrences(of: plural.other, with: plural.one)
        }
        for (placeholder, argument) in zip(placeholders, arguments) {
            let value: String
            switch argument {
            case .string(let s): value = s
            // Matches the catalog's %lld, which prints plain digits without grouping.
            case .integer(let i): value = String(i)
            }
            result = result.replacingOccurrences(of: "{\(placeholder.name)}", with: value)
        }
        return result
    }

    /// The String Catalog format: `{name}` becomes a positional specifier (`%1$@`, `%2$lld`); the
    /// plural span becomes a `%N$#@name@` substitution.
    public static func formatString(_ text: String, placeholders: [Placeholder], plural: PluralForms?) -> String {
        var result = text
        if let plural {
            guard result.contains(plural.other) else { preconditionFailure("plural form not in \(text)") }
            let position = placeholders.firstIndex { $0.name == plural.placeholder }! + 1
            result = result.replacingOccurrences(of: plural.other, with: "%\(position)$#@\(plural.placeholder)@")
        }
        for (offset, placeholder) in placeholders.enumerated() {
            result = result.replacingOccurrences(of: "{\(placeholder.name)}",
                                                 with: "%\(offset + 1)$\(specifier(placeholder.kind))")
        }
        return result
    }

    public static func specifier(_ kind: Placeholder.Kind) -> String {
        kind == .string ? "@" : "lld"
    }
}

/// Times are shown in the Monospace face (Section 4.4.6) in the locale's short time style.
public enum TimestampText {
    public static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar,
                                     timeZone: timeZone)
        return date.formatted(style)
    }
}

/// Verified-of-total bytes ("3.1 of 5.2 GB verified", Section 15.5).
///
/// Decimal units (1 KB = 1000 bytes), one fraction digit for KB and above, the unit chosen by the
/// total. The total is rounded to nearest; the verified amount is rounded down and, while
/// verification is incomplete, kept strictly below the shown total, so the text never claims more
/// verified data than exists (Section 4.4.1, "Say what is true"). Out-of-range input (a negative
/// value, or verified above total) is clamped rather than trapping in a view; the transfer state
/// machine owns that invariant.
public enum ByteProgressText {
    public static let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    public static func parts(verified rawVerified: Int64, total rawTotal: Int64,
                             locale: Locale) -> (verified: String, total: String) {
        let total = max(rawTotal, 0)
        let verified = min(max(rawVerified, 0), total)
        var exponent = 0
        while exponent < units.count - 1, Double(total) >= pow(1000, Double(exponent + 1)) {
            exponent += 1
        }
        if exponent == 0 {
            let format = IntegerFormatStyle<Int64>.number.locale(locale)
            return (verified.formatted(format), "\(total.formatted(format)) \(units[0])")
        }
        let divisor = pow(1000, Double(exponent))
        // Work in tenths of the unit.
        let totalTenths = (Double(total) / divisor * 10).rounded(.toNearestOrAwayFromZero)
        var verifiedTenths = (Double(verified) / divisor * 10).rounded(.down)
        if verified < total, verifiedTenths >= totalTenths {
            verifiedTenths = totalTenths - 1
        }
        let format = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(1))
        return ((verifiedTenths / 10).formatted(format), "\((totalTenths / 10).formatted(format)) \(units[exponent])")
    }
}

/// Durations as "20h 58m" (Section 4.4.6). Whole units, truncated: hours and minutes from one
/// hour up, minutes from one minute up, otherwise seconds.
public enum DurationText {
    public static func components(seconds rawSeconds: Int) -> (key: FormatKey, values: [Int64]) {
        let seconds = max(rawSeconds, 0) // a negative duration is shown as 0s, never trapped on
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return (.durationHoursMinutes, [Int64(hours), Int64(minutes)]) }
        if minutes > 0 { return (.durationMinutes, [Int64(minutes)]) }
        return (.durationSeconds, [Int64(seconds)])
    }

    /// English rendering from the templates (the String Catalog path is in SylviaDesign).
    public static func englishDuration(seconds: Int) -> String {
        let (key, values) = components(seconds: seconds)
        return Template.render(key.text, placeholders: key.placeholders, plural: nil,
                               arguments: values.map { .integer($0) }, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func englishTimeLeft(seconds: Int) -> String {
        Template.render(FormatKey.timeLeft.text, placeholders: FormatKey.timeLeft.placeholders, plural: nil,
                        arguments: [.string(englishDuration(seconds: seconds))],
                        locale: Locale(identifier: "en_US_POSIX"))
    }
}
