import Foundation

public enum CaptureKind: String, Codable, Sendable {
    /// A position only (plan 10.2).
    case bookmark
    /// A bounded excerpt with its original source ranges, optional transcript and notes (plan 10.2).
    case audio
}

public enum ExcerptState: Codable, Equatable, Sendable {
    /// Bookmarks have no excerpt.
    case notRequested
    /// The anchor and note are durable; the excerpt is being (or will be) exported.
    case pending
    case saved(ExportedExcerpt)
    case failed(reason: String, attempts: Int)
}

/// A capture as the spike's store holds it. The product schema is written after G0.4 from this evidence
/// (Contracts/README.md ownership); `quoted_text` is deliberately absent: an audio capture never carries text that
/// was not selected, typed or transcribed (I-04, plan A.1).
public struct CaptureRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var idempotencyKey: String
    public var kind: CaptureKind
    public var editionID: UUID
    /// The timeline revision the user saw. Display only; the ranges below are canonical.
    public var timelineRevision: Int
    /// Bookmark position (file-local).
    public var point: AudioPoint?
    /// Audio capture ranges (file-local, ordered; several when the selection crosses files).
    public var ranges: [AudioRange]
    public var note: String?
    public var excerpt: ExcerptState
    /// UTC timestamps in milliseconds since 1970 (exact round-trip; the portable contract uses RFC 3339).
    public var createdAtMs: Int64
    public var updatedAtMs: Int64
    /// Where the capture came from: "player" or a quick-capture surface and the process that ran it.
    public var origin: String

    /// The status-vocabulary key for this record's current state (plan 4.4.6). Only reachable after the record is
    /// durable, so a bookmark's key is "Saved".
    public var statusKey: VocabularyKey {
        switch excerpt {
        case .notRequested: .saveDone
        case .pending: .audioMomentSaved
        case .saved: .audioExcerptSaved
        case .failed: .audioExcerptNotPreserved
        }
    }

    public var canRetryExport: Bool {
        if case .failed = excerpt { return true }
        return false
    }
}

/// Capture range rules (plan 10.2, 18.3).
public enum CaptureRange {
    public static let defaultLengthMs: Int64 = 30_000
    public static let maximumLengthMs: Int64 = 120_000
    public static let minimumLengthMs: Int64 = 1_000

    public enum RangeError: Error, Equatable, Sendable {
        case startAfterEnd
        case tooShort(Int64)
        case tooLong(Int64)
        case outOfBounds
    }

    /// The default capture: the preceding 30 seconds of source time, clamped to the edition. Near the start of the
    /// edition, where less than the minimum precedes the position, the range runs from 0 for the minimum length.
    public static func preceding(globalMs: Int64, lengthMs: Int64 = defaultLengthMs, durationMs: Int64) -> (start: Int64, end: Int64) {
        let end = min(max(globalMs, 0), durationMs)
        let start = max(0, end - lengthMs)
        if end - start < minimumLengthMs { return (0, min(minimumLengthMs, durationMs)) }
        return (start, end)
    }

    /// Validates a range set through the range handles or the numeric start/end controls.
    public static func validate(startMs: Int64, endMs: Int64, durationMs: Int64) throws {
        guard startMs >= 0, endMs <= durationMs else { throw RangeError.outOfBounds }
        guard startMs < endMs else { throw RangeError.startAfterEnd }
        let length = endMs - startMs
        guard length >= minimumLengthMs else { throw RangeError.tooShort(length) }
        guard length <= maximumLengthMs else { throw RangeError.tooLong(length) }
    }
}
