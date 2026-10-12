import Foundation
import Testing
@testable import SylviaDesignTokens

/// Every "We say" phrase of the Section 4.4.6 table (draft 0.3), re-typed from the plan.
private let planPhrases: [StatusMoment: [String]] = [
    .saving: ["Saving…", "Saved", "Not saved · your text is still here"],
    .importTransfer: ["Queued", "Waiting for {source}", "Receiving", "Verifying", "Preparing", "Needs review",
                      "Ready", "Ready · indexing continues", "Needs attention"],
    .deliveryReceipts: ["Queued on Mac", "Downloaded to phone", "Imported into Sylvia"],
    .capturingAudio: ["Moment saved · preserving audio", "Audio excerpt saved", "Excerpt not preserved · Retry"],
    .askingModel: ["Draft · not sent", "Sending to {host}", "Generated", "Complete", "Interrupted · partial answer"],
    .contextScope: ["Selected passage", "Passage and nearby text", "Relevant passages from this work",
                    "Selected thoughts", "Relevant passages retrieved"],
    .fileLocation: ["On this device", "Not on this device · from {source}", "Record only"],
    .searchCoverage: ["Saved thoughts only", "Book text indexed", "Indexing {n} of {m} chapters", "Text unavailable"],
    .removing: ["Remove download", "Manage retained text", "Remove excerpt audio", "Delete record and thoughts"],
    .endpointDisclosure: ["{host} · hosted", "{host} · local", "{host} · user-managed"],
]

/// Every "We never say" phrase of the table.
private let planForbidden: [StatusMoment: [String]] = [
    .saving: ["Done", "Success"],
    .importTransfer: ["Complete", "Error", "Downloading"],
    .deliveryReceipts: ["Sent", "Delivered"],
    .capturingAudio: ["Clip saved"],
    .askingModel: ["Thinking…", "The AI read your book", "Free with your subscription"],
    .contextScope: ["Whole book", "Understands your library", "The AI read the entire book"],
    .fileLocation: ["Deleted", "Missing", "Broken"],
    .searchCoverage: ["Semantic search", "Searched everything"],
    .removing: ["Delete"],
    .endpointDisclosure: ["Secure", "Private"],
]

private let posix = Locale(identifier: "en_US_POSIX")
private let utc = TimeZone(identifier: "UTC")!

@Suite("Status vocabulary (plan 4.4.6, T54)")
struct VocabularyTests {
    @Test("Every phrase in the plan's table is in the vocabulary, under its moment", arguments: StatusMoment.allCases)
    func planPhrasesPresent(moment: StatusMoment) {
        let texts = moment.entries.map(\.text)
        for phrase in planPhrases[moment]! {
            #expect(texts.contains(phrase), "\(moment): \(phrase)")
        }
    }

    @Test("The vocabulary adds nothing beyond the table except the time, byte and model forms it calls for")
    func noUnplannedPhrases() {
        let planned = Set(planPhrases.values.flatMap { $0 })
        let extras = VocabularyKey.allCases.filter { !planned.contains($0.text) }
        #expect(Set(extras) == [.saveDoneAt, .importBytesVerified, .endpointHostedModel, .endpointLocalModel,
                                .endpointUserManagedModel])
    }

    @Test("Every forbidden phrase of the table is recorded, and behaviors are kept separate")
    func forbiddenRecorded() {
        for moment in StatusMoment.allCases {
            let phrases = moment.forbidden.filter { $0.kind == .phrase }.map(\.text)
            #expect(phrases == planForbidden[moment]!, "\(moment)")
        }
        let behaviors = StatusMoment.allCases.flatMap(\.forbidden).filter { $0.kind == .behavior }.map(\.text)
        #expect(behaviors == ["a dismissed sheet with nothing written", "any transcript text that was not transcribed",
                              "a trash icon on a download"])
    }

    @Test("No moment permits a phrase it forbids")
    func noSelfContradiction() {
        for moment in StatusMoment.allCases {
            let permitted = Set(moment.entries.flatMap(\.englishForms).map { $0.lowercased() })
            for rule in moment.forbidden where rule.kind == .phrase {
                #expect(!permitted.contains(rule.text.lowercased()), "\(moment) permits forbidden \(rule.text)")
            }
        }
    }

    @Test("An unqualified forbidden phrase is not permitted anywhere, nor used as a label")
    func unqualifiedForbiddenNowhere() {
        let everything = Set((VocabularyKey.allCases.flatMap(\.englishForms) + LabelKey.allCases.map(\.text))
            .map { $0.lowercased() })
        for moment in StatusMoment.allCases {
            for rule in moment.forbidden where rule.kind == .phrase && rule.qualifier == nil {
                #expect(!everything.contains(rule.text.lowercased()), "\(rule.text)")
            }
        }
    }

    @Test("Microcopy: sentence case, no exclamation marks")
    func microcopy() {
        let all = VocabularyKey.allCases.flatMap(\.englishForms) + LabelKey.allCases.map(\.text)
            + FormatKey.allCases.map(\.text)
        let properNouns: Set<String> = ["Mac", "Sylvia", "Retry", "AI"]
        for text in all {
            #expect(!text.contains("!"), "\(text)")
            let words = text.replacingOccurrences(of: "·", with: " ").split(separator: " ").map(String.init)
                .filter { !$0.hasPrefix("{") }
            guard let first = words.first else { continue }
            if !text.hasPrefix("{") {
                #expect(first.first!.isUppercase, "starts with a capital: \(text)")
            }
            for word in words.dropFirst() where word.first!.isUppercase {
                #expect(properNouns.contains(word), "sentence case: \(word) in \(text)")
            }
        }
    }

    @Test("Keys are stable, unique, dotted snake case; A.5 keys are kept as sketched")
    func keys() {
        let all = VocabularyKey.allCases.map(\.rawValue) + LabelKey.allCases.map(\.rawValue)
            + FormatKey.allCases.map(\.rawValue)
        #expect(Set(all).count == all.count)
        let pattern = /^[a-z][a-z_]*(\.[a-z][a-z_0-9]*)+$/
        for key in all { #expect(key.wholeMatch(of: pattern) != nil, "\(key)") }
        #expect(VocabularyKey.saveInProgress.rawValue == "save.in_progress")
        #expect(VocabularyKey.saveDone.rawValue == "save.done")
        #expect(VocabularyKey.saveFailed.rawValue == "save.failed")
        #expect(VocabularyKey.importReadyIndexing.rawValue == "import.ready_indexing")
    }

    @Test("Declared placeholders match the template text")
    func placeholders() {
        for key in VocabularyKey.allCases {
            #expect(Template.placeholderNames(in: key.text) == key.placeholders.map(\.name), "\(key)")
        }
        for key in FormatKey.allCases {
            #expect(Template.placeholderNames(in: key.text) == key.placeholders.map(\.name), "\(key)")
        }
    }

    @Test("Every vocabulary key is produced by exactly one kind of typed Status")
    func statusCoversKeys() {
        let samples: [Status] = VocabularyKey.allCases.compactMap { Status(key: $0) } + [
            .savedAt(Date(timeIntervalSince1970: 0)), .waitingFor(source: "Studio"),
            .bytesVerified(verified: 1, total: 2), .sendingTo(host: "h"), .notOnThisDevice(source: "Studio"),
            .indexingChapters(indexed: 1, total: 2),
            .endpoint(host: "h", kind: .hosted, model: nil), .endpoint(host: "h", kind: .local, model: nil),
            .endpoint(host: "h", kind: .userManaged, model: nil), .endpoint(host: "h", kind: .hosted, model: "m"),
            .endpoint(host: "h", kind: .local, model: "m"), .endpoint(host: "h", kind: .userManaged, model: "m"),
        ]
        #expect(Set(samples.map(\.key)) == Set(VocabularyKey.allCases))
        for key in VocabularyKey.allCases where key.placeholders.isEmpty {
            #expect(Status(key: key)?.key == key, "\(key)")
        }
    }

    @Test("Interpolation: source, host, model, n of m, bytes, time")
    func interpolation() {
        #expect(Status.waitingFor(source: "Studio").englishText() == "Waiting for Studio")
        #expect(Status.notOnThisDevice(source: "Studio").englishText() == "Not on this device · from Studio")
        #expect(Status.sendingTo(host: "api.example.com").englishText() == "Sending to api.example.com")
        #expect(Status.endpoint(host: "api.example.com", kind: .hosted, model: "example-model-1").englishText()
            == "api.example.com · hosted · example-model-1")
        #expect(Status.endpoint(host: "studio.local", kind: .local, model: nil).englishText() == "studio.local · local")
        #expect(Status.endpoint(host: "hermes", kind: .userManaged, model: nil).englishText() == "hermes · user-managed")
        #expect(Status.endpoint(host: "hermes", kind: .userManaged, model: "").englishText() == "hermes · user-managed",
                "an empty model identifier is treated as absent")
        #expect(Status.indexingChapters(indexed: 12, total: 40).englishText() == "Indexing 12 of 40 chapters")
        #expect(Status.indexingChapters(indexed: 0, total: 1).englishText() == "Indexing 0 of 1 chapter")
        #expect(Status.bytesVerified(verified: 3_100_000_000, total: 5_200_000_000).englishText()
            == "3.1 of 5.2 GB verified")
        let commit = Date(timeIntervalSince1970: 1_791_208_920) // 2026-10-05T14:02:00Z
        #expect(Status.savedAt(commit).englishText(locale: Locale(identifier: "en_GB"), timeZone: utc) == "Saved 14:02")
    }

    @Test("Bytes: unit chosen by the total; verified rounded down and never shown equal to an unfinished total",
          arguments: [
              (Int64(3_100_000_000), Int64(5_200_000_000), "3.1", "5.2 GB"),
              (5_199_000_000, 5_200_000_000, "5.1", "5.2 GB"),
              (5_239_999_999, 5_240_000_000, "5.1", "5.2 GB"),
              (5_240_000_000, 5_240_000_000, "5.2", "5.2 GB"),
              (49_999_999, 5_200_000_000, "0.0", "5.2 GB"),
              (1_500, 2_000, "1.5", "2.0 KB"),
              (500, 900, "500", "900 bytes"),
              (0, 0, "0", "0 bytes"),
              (999, 1_000, "0.9", "1.0 KB"),
              (612_000_000, 612_000_000, "612.0", "612.0 MB"),
          ])
    func bytes(verified: Int64, total: Int64, shownVerified: String, shownTotal: String) {
        let parts = ByteProgressText.parts(verified: verified, total: total, locale: posix)
        #expect(parts.verified == shownVerified)
        #expect(parts.total == shownTotal)
    }

    @Test("Out-of-range bytes and durations are clamped, not trapped")
    func clamping() {
        let over = ByteProgressText.parts(verified: 9_000, total: 5_000, locale: posix)
        #expect(over.verified == "5.0" && over.total == "5.0 KB")
        let negative = ByteProgressText.parts(verified: -1, total: -1, locale: posix)
        #expect(negative.verified == "0" && negative.total == "0 bytes")
        #expect(DurationText.englishDuration(seconds: -5) == "0s")
    }

    @Test("Bytes use the locale's decimal separator")
    func bytesLocale() {
        let parts = ByteProgressText.parts(verified: 3_100_000_000, total: 5_200_000_000, locale: Locale(identifier: "de_DE"))
        #expect(parts.verified == "3,1")
        #expect(parts.total == "5,2 GB")
    }

    @Test("Property: an unfinished transfer never displays verified >= total")
    func bytesProperty() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<5000 {
            let total = Int64.random(in: 1...8_000_000_000_000, using: &generator)
            let verified = Int64.random(in: 0...total, using: &generator)
            let parts = ByteProgressText.parts(verified: verified, total: total, locale: posix)
            let shownTotal = Double(parts.total.split(separator: " ")[0])!
            let shownVerified = Double(parts.verified)!
            if verified < total {
                #expect(shownVerified < shownTotal, "\(verified) of \(total) shown as \(parts)")
            } else {
                #expect(shownVerified == shownTotal)
            }
        }
    }

    @Test("Durations: 20h 58m left; truncated whole units", arguments: [
        (75_480, "20h 58m"), (75_539, "20h 58m"), (3_600, "1h 0m"), (60, "1m"), (59, "59s"), (0, "0s"),
    ])
    func durations(seconds: Int, text: String) {
        #expect(DurationText.englishDuration(seconds: seconds) == text)
        #expect(DurationText.englishTimeLeft(seconds: seconds) == "\(text) left")
    }

    @Test("Import state mapping (Section 4.4.6, draft 0.3)")
    func importMapping() {
        let expected: [ImportState: (VocabularyKey, StatusGlyph)] = [
            .created: (.importQueued, .dot), .acquiring: (.importReceiving, .dot),
            .staged: (.importVerifying, .dot), .validating: (.importVerifying, .dot),
            .identifying: (.importPreparing, .dot), .committing: (.importPreparing, .dot),
            .needsReview: (.importNeedsReview, .triangle), .ready: (.importReady, .check),
            .waitingForSource: (.importWaitingForSource, .dot),
            .waitingForSpace: (.importNeedsAttention, .triangle), .unsupported: (.importNeedsAttention, .triangle),
            .failedRetryable: (.importNeedsAttention, .triangle), .failedFinal: (.importNeedsAttention, .triangle),
        ]
        for state in ImportState.allCases {
            let p = state.presentation()
            if state == .cancelled {
                #expect(p == nil, "cancelled items leave the Inbox")
                continue
            }
            #expect(p?.phrase == expected[state]!.0, "\(state)")
            #expect(p?.glyph == expected[state]!.1, "\(state)")
        }
        #expect(ImportState.ready.presentation(indexingContinues: true)?.phrase == .importReadyIndexing)
        #expect(ImportState.waitingForSource.presentation()?.marker == .pending, "waiting uses the pending dot")
        #expect(ImportState.needsReview.presentation()?.marker == .attention, "needs review uses the attention glyph")
        for state in [ImportState.waitingForSpace, .unsupported, .failedRetryable, .failedFinal] {
            #expect(state.presentation()?.requiresReasonAndNextStep == true)
        }
        #expect(ImportState.allCases.map(\.rawValue) == [
            "created", "acquiring", "staged", "validating", "identifying", "needs_review", "committing", "ready",
            "waiting_for_source", "waiting_for_space", "unsupported", "failed_retryable", "failed_final", "cancelled",
        ])
    }

    @Test("Nothing claims Ready or Complete for a state that is not ready")
    func noFalseCompletion() {
        for state in ImportState.allCases where state != .ready {
            let phrase = state.presentation()?.phrase
            #expect(phrase != .importReady && phrase != .importReadyIndexing, "\(state)")
        }
    }
}
