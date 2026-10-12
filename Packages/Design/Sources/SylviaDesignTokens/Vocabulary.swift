import Foundation

/// The moments of the status vocabulary table (plan Section 4.4.6), each tied to a state machine.
public enum StatusMoment: String, CaseIterable, Sendable, Codable {
    case saving
    case importTransfer = "import_transfer"
    case deliveryReceipts = "delivery_receipts"
    case capturingAudio = "capturing_audio"
    case askingModel = "asking_model"
    case contextScope = "context_scope"
    case fileLocation = "file_location"
    case searchCoverage = "search_coverage"
    case removing
    case endpointDisclosure = "endpoint_disclosure"

    public var title: String {
        switch self {
        case .saving: "Saving a thought"
        case .importTransfer: "Import and transfer"
        case .deliveryReceipts: "Delivery receipts (Mac companion)"
        case .capturingAudio: "Capturing audio"
        case .askingModel: "Asking a model"
        case .contextScope: "Context scope"
        case .fileLocation: "Where a file is"
        case .searchCoverage: "Search coverage"
        case .removing: "Removing things"
        case .endpointDisclosure: "Endpoint disclosure"
        }
    }

    public var stateMachine: String {
        switch self {
        case .saving: "Section 11.1 capture transaction"
        case .importTransfer: "Section 8.2; Section 15.5"
        case .deliveryReceipts: "Section 16.2"
        case .capturingAudio: "Section 10.2"
        case .askingModel: "Section 14.4"
        case .contextScope: "Section 13.1"
        case .fileLocation: "Sections 7.1, 12"
        case .searchCoverage: "Section 11.3"
        case .removing: "Section 17.2"
        case .endpointDisclosure: "Section 14.2"
        }
    }

    /// "We never say", verbatim from Section 4.4.6, split into lintable phrases and behaviors.
    public var forbidden: [ForbiddenRule] {
        switch self {
        case .saving:
            [.phrase("Done"), .phrase("Success"), .behavior("a dismissed sheet with nothing written")]
        case .importTransfer:
            [.phrase("Complete", qualifier: "before Ready"), .phrase("Error"),
             .phrase("Downloading", qualifier: "for a Mac transfer that is verified by parts")]
        case .deliveryReceipts:
            [.phrase("Sent"), .phrase("Delivered", qualifier: "as a claim that the item was imported")]
        case .capturingAudio:
            [.phrase("Clip saved", qualifier: "before export"),
             .behavior("any transcript text that was not transcribed")]
        case .askingModel:
            [.phrase("Thinking…"), .phrase("The AI read your book"), .phrase("Free with your subscription")]
        case .contextScope:
            [.phrase("Whole book", qualifier: "unless it truly fits and was chosen"),
             .phrase("Understands your library"), .phrase("The AI read the entire book")]
        case .fileLocation:
            [.phrase("Deleted"), .phrase("Missing"), .phrase("Broken")]
        case .searchCoverage:
            [.phrase("Semantic search"), .phrase("Searched everything")]
        case .removing:
            [.phrase("Delete", qualifier: "alone"), .behavior("a trash icon on a download")]
        case .endpointDisclosure:
            [.phrase("Secure", qualifier: "as an unqualified claim"),
             .phrase("Private", qualifier: "as an unqualified claim")]
        }
    }

    public var entries: [VocabularyKey] { VocabularyKey.allCases.filter { $0.moment == self } }
}

/// One "We never say" item.
public struct ForbiddenRule: Sendable, Hashable {
    public enum Kind: String, Sendable, Codable {
        /// A string that must not be shown (lint rejects it as a literal in UI targets).
        case phrase
        /// A behavior that cannot be detected from a string (checked by component and flow tests).
        case behavior
    }

    public let kind: Kind
    public let text: String
    /// When set, the phrase is forbidden only in this sense; the same word may be a permitted
    /// phrase of another moment (for example "Complete" when asking a model).
    public let qualifier: String?

    public static func phrase(_ text: String, qualifier: String? = nil) -> ForbiddenRule {
        ForbiddenRule(kind: .phrase, text: text, qualifier: qualifier)
    }

    public static func behavior(_ text: String) -> ForbiddenRule {
        ForbiddenRule(kind: .behavior, text: text, qualifier: nil)
    }
}

/// A placeholder in a template (`{name}` in the text).
public struct Placeholder: Sendable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case string
        case integer
    }

    public let name: String
    public let kind: Kind
    public let meaning: String
}

/// English plural forms for one integer placeholder (String Catalog substitution).
public struct PluralForms: Sendable, Hashable {
    public let placeholder: String
    /// The text that replaces `{placeholder} …` when the count is one, for example "{m} chapter".
    public let one: String
    /// The same for every other count; must appear verbatim in the entry's template.
    public let other: String
}

/// Keys of the status vocabulary. Raw values are the stable localization keys (Section 4.4.9);
/// the four keys in the Appendix A.5 sketch are kept as written there.
public enum VocabularyKey: String, CaseIterable, Sendable, Codable {
    case saveInProgress = "save.in_progress"
    case saveDone = "save.done"
    case saveDoneAt = "save.done_at"
    case saveFailed = "save.failed"
    case importQueued = "import.queued"
    case importWaitingForSource = "import.waiting_for_source"
    case importReceiving = "import.receiving"
    case importBytesVerified = "import.bytes_verified"
    case importVerifying = "import.verifying"
    case importPreparing = "import.preparing"
    case importNeedsReview = "import.needs_review"
    case importReady = "import.ready"
    case importReadyIndexing = "import.ready_indexing"
    case importNeedsAttention = "import.needs_attention"
    case deliveryQueuedOnMac = "delivery.queued_on_mac"
    case deliveryDownloadedToPhone = "delivery.downloaded_to_phone"
    case deliveryImportedIntoSylvia = "delivery.imported_into_sylvia"
    case audioMomentSaved = "audio.moment_saved"
    case audioExcerptSaved = "audio.excerpt_saved"
    case audioExcerptNotPreserved = "audio.excerpt_not_preserved"
    case askDraftNotSent = "ask.draft_not_sent"
    case askSending = "ask.sending"
    case askGenerated = "ask.generated"
    case askComplete = "ask.complete"
    case askInterrupted = "ask.interrupted"
    case scopeSelectedPassage = "scope.selected_passage"
    case scopePassageAndNearby = "scope.passage_and_nearby"
    case scopeWorkSearch = "scope.work_search"
    case scopeSelectedThoughts = "scope.selected_thoughts"
    case scopePassagesRetrieved = "scope.passages_retrieved"
    case fileOnDevice = "file.on_device"
    case fileNotOnDevice = "file.not_on_device"
    case fileRecordOnly = "file.record_only"
    case searchSavedThoughtsOnly = "search.saved_thoughts_only"
    case searchBookTextIndexed = "search.book_text_indexed"
    case searchIndexing = "search.indexing"
    case searchTextUnavailable = "search.text_unavailable"
    case removeDownload = "remove.download"
    case removeManageRetainedText = "remove.manage_retained_text"
    case removeExcerptAudio = "remove.excerpt_audio"
    case removeDeleteRecordAndThoughts = "remove.delete_record_and_thoughts"
    case endpointHosted = "endpoint.hosted"
    case endpointLocal = "endpoint.local"
    case endpointUserManaged = "endpoint.user_managed"
    case endpointHostedModel = "endpoint.hosted_model"
    case endpointLocalModel = "endpoint.local_model"
    case endpointUserManagedModel = "endpoint.user_managed_model"

    public var moment: StatusMoment {
        switch self {
        case .saveInProgress, .saveDone, .saveDoneAt, .saveFailed: .saving
        case .importQueued, .importWaitingForSource, .importReceiving, .importBytesVerified, .importVerifying,
             .importPreparing, .importNeedsReview, .importReady, .importReadyIndexing, .importNeedsAttention:
            .importTransfer
        case .deliveryQueuedOnMac, .deliveryDownloadedToPhone, .deliveryImportedIntoSylvia: .deliveryReceipts
        case .audioMomentSaved, .audioExcerptSaved, .audioExcerptNotPreserved: .capturingAudio
        case .askDraftNotSent, .askSending, .askGenerated, .askComplete, .askInterrupted: .askingModel
        case .scopeSelectedPassage, .scopePassageAndNearby, .scopeWorkSearch, .scopeSelectedThoughts,
             .scopePassagesRetrieved:
            .contextScope
        case .fileOnDevice, .fileNotOnDevice, .fileRecordOnly: .fileLocation
        case .searchSavedThoughtsOnly, .searchBookTextIndexed, .searchIndexing, .searchTextUnavailable: .searchCoverage
        case .removeDownload, .removeManageRetainedText, .removeExcerptAudio, .removeDeleteRecordAndThoughts: .removing
        case .endpointHosted, .endpointLocal, .endpointUserManaged, .endpointHostedModel, .endpointLocalModel,
             .endpointUserManagedModel:
            .endpointDisclosure
        }
    }

    /// English text. `{name}` marks a placeholder.
    public var text: String {
        switch self {
        case .saveInProgress: "Saving…"
        case .saveDone: "Saved"
        case .saveDoneAt: "Saved {time}"
        case .saveFailed: "Not saved · your text is still here"
        case .importQueued: "Queued"
        case .importWaitingForSource: "Waiting for {source}"
        case .importReceiving: "Receiving"
        case .importBytesVerified: "{verified} of {total} verified"
        case .importVerifying: "Verifying"
        case .importPreparing: "Preparing"
        case .importNeedsReview: "Needs review"
        case .importReady: "Ready"
        case .importReadyIndexing: "Ready · indexing continues"
        case .importNeedsAttention: "Needs attention"
        case .deliveryQueuedOnMac: "Queued on Mac"
        case .deliveryDownloadedToPhone: "Downloaded to phone"
        case .deliveryImportedIntoSylvia: "Imported into Sylvia"
        case .audioMomentSaved: "Moment saved · preserving audio"
        case .audioExcerptSaved: "Audio excerpt saved"
        case .audioExcerptNotPreserved: "Excerpt not preserved · Retry"
        case .askDraftNotSent: "Draft · not sent"
        case .askSending: "Sending to {host}"
        case .askGenerated: "Generated"
        case .askComplete: "Complete"
        case .askInterrupted: "Interrupted · partial answer"
        case .scopeSelectedPassage: "Selected passage"
        case .scopePassageAndNearby: "Passage and nearby text"
        case .scopeWorkSearch: "Relevant passages from this work"
        case .scopeSelectedThoughts: "Selected thoughts"
        case .scopePassagesRetrieved: "Relevant passages retrieved"
        case .fileOnDevice: "On this device"
        case .fileNotOnDevice: "Not on this device · from {source}"
        case .fileRecordOnly: "Record only"
        case .searchSavedThoughtsOnly: "Saved thoughts only"
        case .searchBookTextIndexed: "Book text indexed"
        case .searchIndexing: "Indexing {n} of {m} chapters"
        case .searchTextUnavailable: "Text unavailable"
        case .removeDownload: "Remove download"
        case .removeManageRetainedText: "Manage retained text"
        case .removeExcerptAudio: "Remove excerpt audio"
        case .removeDeleteRecordAndThoughts: "Delete record and thoughts"
        case .endpointHosted: "{host} · hosted"
        case .endpointLocal: "{host} · local"
        case .endpointUserManaged: "{host} · user-managed"
        case .endpointHostedModel: "{host} · hosted · {model}"
        case .endpointLocalModel: "{host} · local · {model}"
        case .endpointUserManagedModel: "{host} · user-managed · {model}"
        }
    }

    public var placeholders: [Placeholder] {
        switch self {
        case .saveDoneAt:
            [Placeholder(name: "time", kind: .string, meaning: "Time of the durable commit, short time style, Monospace face")]
        case .importWaitingForSource, .fileNotOnDevice:
            [Placeholder(name: "source", kind: .string, meaning: "Display name of the source (for example a paired Mac)")]
        case .importBytesVerified:
            [Placeholder(name: "verified", kind: .string, meaning: "Verified bytes in the total's unit, rounded down, without the unit"),
             Placeholder(name: "total", kind: .string, meaning: "Total bytes with unit, for example 5.2 GB")]
        case .askSending, .endpointHosted, .endpointLocal, .endpointUserManaged:
            [Placeholder(name: "host", kind: .string, meaning: "Endpoint host name")]
        case .endpointHostedModel, .endpointLocalModel, .endpointUserManagedModel:
            [Placeholder(name: "host", kind: .string, meaning: "Endpoint host name"),
             Placeholder(name: "model", kind: .string, meaning: "Model identifier as configured")]
        case .searchIndexing:
            [Placeholder(name: "n", kind: .integer, meaning: "Chapters indexed so far"),
             Placeholder(name: "m", kind: .integer, meaning: "Chapters in the work")]
        default:
            []
        }
    }

    public var plural: PluralForms? {
        switch self {
        case .searchIndexing: PluralForms(placeholder: "m", one: "{m} chapter", other: "{m} chapters")
        default: nil
        }
    }

    /// Where the plan states the phrase.
    public var source: String {
        switch self {
        case .saveDoneAt: "Section 4.4.6 (\"Saved\" with time); format from the capture-sheet board"
        case .importBytesVerified: "Section 4.4.6 (verified-of-total bytes); Section 15.5 (\"3.1 of 5.2 GB verified\")"
        case .importNeedsReview, .importWaitingForSource: "Section 4.4.6 (draft 0.3 addition); Section 8.2"
        case .scopePassagesRetrieved: "Section 4.4.6 (draft 0.3 addition); Section 13.1"
        case .deliveryQueuedOnMac, .deliveryDownloadedToPhone, .deliveryImportedIntoSylvia:
            "Section 4.4.6 (draft 0.3 addition); Section 16.2"
        case .endpointHostedModel, .endpointLocalModel, .endpointUserManagedModel:
            "Section 4.4.6 (\"with the model identifier\"); Section 14.2"
        default: "Section 4.4.6"
        }
    }

    public var comment: String {
        "\(moment.title) (\(moment.stateMachine)). \(source)."
    }

    /// Every concrete English string this key can produce, as a template (one per plural form).
    public var englishForms: [String] {
        guard let plural else { return [text] }
        return [text, text.replacingOccurrences(of: plural.other, with: plural.one)]
    }
}

/// Labels that are not statuses: marker labels, filter chips, symbol accessibility labels and the
/// fixed captions of Sections 4.4.5 and 4.4.7. Not linted as status phrases.
public enum LabelKey: String, CaseIterable, Sendable, Codable {
    case markerQuote = "marker.quote"
    case markerNote = "marker.note"
    case markerAudio = "marker.audio"
    case markerGenerated = "marker.generated"
    case markerWord = "marker.word"
    case markerAttention = "marker.attention"
    case markerPendingQueued = "marker.pending.queued"
    case markerPendingWaiting = "marker.pending.waiting"
    case markerUnknownKind = "marker.unknown_kind"
    case filterAll = "filter.all"
    case filterQuotes = "filter.quotes"
    case filterNotes = "filter.notes"
    case filterAudio = "filter.audio"
    case filterGenerated = "filter.generated"
    case filterWords = "filter.words"
    case symbolPrompt = "symbol.prompt"
    case symbolCapture = "symbol.capture"
    case controlCaptureRecent = "control.capture_recent"
    case captureYourNote = "capture.your_note"
    case audioNoTranscript = "audio.no_transcript"
    case audioTranscript = "audio.transcript"
    case areaLibrary = "area.library"
    case areaThoughts = "area.thoughts"
    case areaInbox = "area.inbox"
    case navSearch = "nav.search"
    case navSettings = "nav.settings"
    case navBack = "nav.back"
    case controlPlay = "control.play"
    case controlPause = "control.pause"
    case controlOpenPlayerHint = "control.open_player_hint"
    case controlPlayExcerpt = "control.play_excerpt"
    case controlPauseExcerpt = "control.pause_excerpt"
    case captureSheetTitle = "capture.sheet_title"
    case actionSave = "action.save"
    case actionSaveAgainHint = "action.save_again_hint"
    case actionCloseHint = "action.close_hint"
    case actionLookUp = "action.look_up"
    case actionAsk = "action.ask"
    case actionHighlight = "action.highlight"
    case actionNote = "action.note"
    case captureStart = "capture.start"
    case captureEnd = "capture.end"
    case captureLength = "capture.length"
    case controlStartEarlier = "control.start_earlier"
    case controlStartLater = "control.start_later"
    case controlEndEarlier = "control.end_earlier"
    case controlEndLater = "control.end_later"
    case ratingLabel = "rating.label"
    case ratingClear = "rating.clear"
    case ratingNone = "rating.none"
    case readerSettings = "reader.settings"
    case readerBookmark = "reader.bookmark"
    case readerSearch = "reader.search"
    case citationUnresolvedExplanation = "citation.unresolved_explanation"
    case readerHighlighted = "reader.highlighted"
    case readerSavedThought = "reader.saved_thought"

    public var text: String {
        switch self {
        case .markerQuote: "Quote"
        case .markerNote: "Note"
        case .markerAudio: "Audio"
        case .markerGenerated: "Generated"
        case .markerWord: "Word"
        case .markerAttention: "Needs attention"
        case .markerPendingQueued: "Queued"
        case .markerPendingWaiting: "Waiting"
        case .markerUnknownKind: "Unknown kind"
        case .filterAll: "All"
        case .filterQuotes: "Quotes"
        case .filterNotes: "Notes"
        case .filterAudio: "Audio"
        case .filterGenerated: "Generated"
        case .filterWords: "Words"
        case .symbolPrompt: "Generated"
        case .symbolCapture: "Capture"
        case .controlCaptureRecent: "Capture the last 30 seconds"
        case .captureYourNote: "Your note"
        case .audioNoTranscript: "No transcript"
        case .audioTranscript: "Transcript"
        case .areaLibrary: "Library"
        case .areaThoughts: "Thoughts"
        case .areaInbox: "Inbox"
        case .navSearch: "Search"
        case .navSettings: "Settings"
        case .navBack: "Back"
        case .controlPlay: "Play"
        case .controlPause: "Pause"
        case .controlOpenPlayerHint: "Opens the player"
        case .controlPlayExcerpt: "Play excerpt"
        case .controlPauseExcerpt: "Pause excerpt"
        case .captureSheetTitle: "Save to thoughts"
        case .actionSave: "Save"
        case .actionSaveAgainHint: "Tries to save again"
        case .actionCloseHint: "Closes the sheet"
        case .actionLookUp: "Look up"
        case .actionAsk: "Ask"
        case .actionHighlight: "Highlight"
        case .actionNote: "Note"
        case .captureStart: "Start"
        case .captureEnd: "End"
        case .captureLength: "Length"
        case .controlStartEarlier: "Start earlier"
        case .controlStartLater: "Start later"
        case .controlEndEarlier: "End earlier"
        case .controlEndLater: "End later"
        case .ratingLabel: "Rating"
        case .ratingClear: "Clear rating"
        case .ratingNone: "No rating"
        case .readerSettings: "Reader settings"
        case .readerBookmark: "Bookmark"
        case .readerSearch: "Search in book"
        case .citationUnresolvedExplanation: "Struck-through citations do not match any passage that was sent."
        case .readerHighlighted: "Highlighted"
        case .readerSavedThought: "Saved thought here"
        }
    }

    public var comment: String {
        switch self {
        case .markerQuote, .markerNote, .markerAudio, .markerGenerated, .markerWord, .markerAttention,
             .markerPendingQueued, .markerPendingWaiting:
            "Marker label (Section 4.4.5), shown uppercase in the Micro role."
        case .markerUnknownKind:
            "Pending marker label for a capture whose kind is empty or only white space; any other unrecognized kind shows its raw kind (Appendix A.1). Shown uppercase in the Micro role."
        case .filterAll, .filterQuotes, .filterNotes, .filterAudio, .filterGenerated, .filterWords:
            "Thoughts filter chip (Section 4.4.5)."
        case .symbolPrompt: "Accessibility label of the Generated prompt glyph (sylvia.prompt)."
        case .symbolCapture: "Accessibility label of the bracket capture glyph (sylvia.capture)."
        case .controlCaptureRecent: "Mini-player and player capture control (Section 4.4.7)."
        case .captureYourNote: "Prefix of the user's own note under a capture (Section 4.4.5)."
        case .audioNoTranscript: "Caption of an audio capture until a transcript exists (Section 4.4.5)."
        case .audioTranscript: "Label above a transcript, which is always labelled as one (Section 10.2, I-04)."
        case .areaLibrary: "Primary area: tab bar item and iPad sidebar row (Section 4.1, 4.4.7)."
        case .areaThoughts: "Primary area: tab bar item and iPad sidebar row (Section 4.1, 4.4.7)."
        case .areaInbox: "Primary area: tab bar item and iPad sidebar row (Section 4.1, 4.4.7)."
        case .navSearch: "Navigation bar icon button (Section 4.4.7)."
        case .navSettings: "Navigation bar icon button (Section 4.4.7)."
        case .navBack: "Navigation bar and reader chrome back button (Section 4.4.7)."
        case .controlPlay: "Mini-player play control (Section 4.4.7)."
        case .controlPause: "Mini-player pause control (Section 4.4.7)."
        case .controlOpenPlayerHint: "Accessibility hint of the mini-player's title area."
        case .controlPlayExcerpt: "Audio block play control; preview playback never moves the main position (Section 10.3)."
        case .controlPauseExcerpt: "Audio block pause control."
        case .captureSheetTitle: "Capture sheet title (Section 4.1 reader/player sheet)."
        case .actionSave: "Capture sheet primary button before the first save; afterwards the button shows the save state (Section 4.4.7)."
        case .actionSaveAgainHint: "Accessibility hint of the capture sheet button after a failed save."
        case .actionCloseHint: "Accessibility hint of the capture sheet button once the capture is saved."
        case .actionLookUp: "Capture sheet and selection menu action (Section 4.4.7)."
        case .actionAsk: "Capture sheet and selection menu action (Section 4.4.7)."
        case .actionHighlight: "Selection menu action (Section 4.4.7)."
        case .actionNote: "Selection menu action (Section 4.4.7)."
        case .captureStart: "Audio range start control (Section 10.2, numeric start and end)."
        case .captureEnd: "Audio range end control (Section 10.2)."
        case .captureLength: "Audio range length caption (Section 10.2)."
        case .controlStartEarlier: "Audio range: move the start one step earlier."
        case .controlStartLater: "Audio range: move the start one step later."
        case .controlEndEarlier: "Audio range: move the end one step earlier."
        case .controlEndLater: "Audio range: move the end one step later."
        case .ratingLabel: "Rating control accessibility label (Section 12)."
        case .ratingClear: "Separate action that clears a rating; clearing is not zero (Section 4.4.7, 12)."
        case .ratingNone: "Rating value when none is set."
        case .readerSettings: "Reader chrome \"Aa\" button (Section 4.4.7, 9.1)."
        case .readerBookmark: "Reader chrome bookmark toggle; selected when the position is bookmarked."
        case .readerSearch: "Reader chrome search button."
        case .citationUnresolvedExplanation: "One-line explanation under a generated answer with unresolved citations (Section 13.4)."
        case .readerHighlighted: "Spoken with a reading paragraph that holds a highlight, so it is not carried by color and underline alone (Section 4.4.8)."
        case .readerSavedThought: "Accessibility label of the reader's margin dot that marks a saved thought (Section 4.4.8)."
        }
    }
}

/// Formats for durations (Section 4.4.6 microcopy: "20h 58m left").
public enum FormatKey: String, CaseIterable, Sendable, Codable {
    case durationHoursMinutes = "duration.hours_minutes"
    case durationMinutes = "duration.minutes"
    case durationSeconds = "duration.seconds"
    case timeLeft = "duration.left"
    case positionChapter = "position.chapter"
    case positionPart = "position.part"
    case ratingValue = "rating.value"
    case citationResolved = "citation.resolved"
    case citationUnresolved = "citation.unresolved"

    public var text: String {
        switch self {
        case .durationHoursMinutes: "{hours}h {minutes}m"
        case .durationMinutes: "{minutes}m"
        case .durationSeconds: "{seconds}s"
        case .timeLeft: "{duration} left"
        case .positionChapter: "Chapter {n} of {m}"
        case .positionPart: "Part {n} of {m}"
        case .ratingValue: "{stars} of 5 stars"
        case .citationResolved: "Citation {id}"
        case .citationUnresolved: "Unresolved citation {id}"
        }
    }

    public var placeholders: [Placeholder] {
        switch self {
        case .durationHoursMinutes:
            [Placeholder(name: "hours", kind: .integer, meaning: "Whole hours"),
             Placeholder(name: "minutes", kind: .integer, meaning: "Whole minutes after the hours")]
        case .durationMinutes: [Placeholder(name: "minutes", kind: .integer, meaning: "Whole minutes")]
        case .durationSeconds: [Placeholder(name: "seconds", kind: .integer, meaning: "Whole seconds")]
        case .timeLeft: [Placeholder(name: "duration", kind: .string, meaning: "A formatted duration")]
        case .positionChapter, .positionPart:
            [Placeholder(name: "n", kind: .integer, meaning: "Current chapter or part, 1-based"),
             Placeholder(name: "m", kind: .integer, meaning: "Chapters or parts in the edition")]
        case .ratingValue:
            [Placeholder(name: "stars", kind: .string, meaning: "Stars in half steps, locale-formatted (for example 3.5)")]
        case .citationResolved, .citationUnresolved:
            [Placeholder(name: "id", kind: .string, meaning: "Citation label as shown on the chip (for example c1)")]
        }
    }

    public var comment: String {
        switch self {
        case .durationHoursMinutes, .durationMinutes, .durationSeconds, .timeLeft:
            "Duration microcopy (Section 4.4.6): durations as \"20h 58m left\"."
        case .positionChapter, .positionPart:
            "Position caption (Section 4.4.6: positions as chapter and percent; Section 4.4.7 progress rule)."
        case .ratingValue: "Rating accessibility value (Section 12: half steps stored as integer 1-10)."
        case .citationResolved, .citationUnresolved:
            "Citation chip accessibility label (Section 13.4: unresolved citations stay visibly unresolved)."
        }
    }
}

/// Section 8.2 import states (persisted names).
public enum ImportState: String, CaseIterable, Sendable, Codable {
    case created
    case acquiring
    case staged
    case validating
    case identifying
    case needsReview = "needs_review"
    case committing
    case ready
    case waitingForSource = "waiting_for_source"
    case waitingForSpace = "waiting_for_space"
    case unsupported
    case failedRetryable = "failed_retryable"
    case failedFinal = "failed_final"
    case cancelled
}

/// How an import state is shown (Section 4.4.6, "Import state mapping"; Section 4.4.7 pills).
public struct ImportStatePresentation: Sendable, Hashable {
    public let phrase: VocabularyKey
    public let glyph: StatusGlyph
    /// The marker whose text and tint the pill uses.
    public let marker: Marker?
    public let textColor: ColorToken
    public let fill: ColorToken
    /// "Needs attention" is always paired with a reason and a next step.
    public let requiresReasonAndNextStep: Bool
}

extension ImportState {
    /// The phrase and pill for this state, or nil when the item leaves the Inbox (`cancelled`).
    /// `indexingContinues` selects "Ready · indexing continues" for `ready`.
    public func presentation(indexingContinues: Bool = false) -> ImportStatePresentation? {
        let pending = { (key: VocabularyKey) in
            ImportStatePresentation(phrase: key, glyph: .dot, marker: .pending, textColor: .markerPendingText,
                                    fill: .markerPendingTint, requiresReasonAndNextStep: false)
        }
        switch self {
        case .created: return pending(.importQueued)
        case .acquiring: return pending(.importReceiving)
        case .staged, .validating: return pending(.importVerifying)
        case .identifying, .committing: return pending(.importPreparing)
        case .waitingForSource: return pending(.importWaitingForSource)
        case .needsReview:
            return ImportStatePresentation(phrase: .importNeedsReview, glyph: .triangle, marker: .attention,
                                           textColor: .markerAttentionText, fill: .markerAttentionTint,
                                           requiresReasonAndNextStep: false)
        case .ready:
            return ImportStatePresentation(phrase: indexingContinues ? .importReadyIndexing : .importReady,
                                           glyph: .check, marker: nil, textColor: .pine, fill: .pineTint,
                                           requiresReasonAndNextStep: false)
        case .waitingForSpace, .unsupported, .failedRetryable, .failedFinal:
            return ImportStatePresentation(phrase: .importNeedsAttention, glyph: .triangle, marker: .attention,
                                           textColor: .markerAttentionText, fill: .markerAttentionTint,
                                           requiresReasonAndNextStep: true)
        case .cancelled:
            return nil
        }
    }
}
