import Foundation

/// Stable status-vocabulary keys for the states this spike shows (plan 4.4.6, 4.4.9). State machines expose keys,
/// never phrases. The raw values mirror the keys of the design package (`SylviaDesignTokens.VocabularyKey` on the
/// G0.6 branch), so integration swaps this enum for the package's without changing any key. Until then the harness
/// resolves keys through `SpikePhrases`, a verbatim copy of the plan's table that is Stage 0 harness chrome and is
/// never shipped.
public enum VocabularyKey: String, CaseIterable, Codable, Sendable {
    // Saving a thought (plan 11.1)
    case saveInProgress = "save.in_progress"
    case saveDone = "save.done"
    case saveFailed = "save.failed"
    // Capturing audio (plan 10.2)
    case audioMomentSaved = "audio.moment_saved"
    case audioExcerptSaved = "audio.excerpt_saved"
    case audioExcerptNotPreserved = "audio.excerpt_not_preserved"
}

/// A key this spike needs that the plan's vocabulary does not have yet. It is a proposal for the design package
/// owner (G0.6), listed in the G0.4 report; the harness shows the key itself, not an invented phrase.
public enum ProposedVocabularyKey: String, CaseIterable, Codable, Sendable {
    /// A quick-capture surface was used with no moment to capture: nothing is loaded in the player, or the loaded book
    /// has not played in this process (review R6-01). Nothing was written.
    case audioNothingToCapture = "audio.nothing_to_capture"
    /// The durable write of a moment (an audio capture or a bookmark, which have no text) failed: nothing was saved.
    /// `save.failed` ("Not saved · your text is still here") is the note editor's phrase and would be untrue here
    /// (review R2-04).
    case audioMomentNotSaved = "audio.moment_not_saved"
    /// Some members of the loaded edition cannot play on this device (not on this device, a missing file, or a file
    /// that does not decode): plan 10.1 asks for an incomplete-edition warning, and the vocabulary has no phrase for
    /// it (review R6-02). Each such member can say where it is with the existing `file.not_on_device` key.
    case audioEditionIncomplete = "audio.edition_incomplete"
}

/// Harness-only phrase lookup: the exact plan 4.4.6 phrases for the keys above. Product targets resolve keys
/// through the design package instead.
public enum SpikePhrases {
    public static func phrase(_ key: VocabularyKey) -> String {
        switch key {
        case .saveInProgress: "Saving…"
        case .saveDone: "Saved"
        case .saveFailed: "Not saved · your text is still here"
        case .audioMomentSaved: "Moment saved · preserving audio"
        case .audioExcerptSaved: "Audio excerpt saved"
        case .audioExcerptNotPreserved: "Excerpt not preserved · Retry"
        }
    }

    /// A proposed key has no approved phrase; the harness shows the key so nobody mistakes it for product copy.
    public static func phrase(_ key: ProposedVocabularyKey) -> String { "[\(key.rawValue)]" }
}
