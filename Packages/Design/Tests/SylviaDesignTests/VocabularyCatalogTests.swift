import Foundation
import Testing
@testable import SylviaDesign

private let posix = Locale(identifier: "en_US_POSIX")
private let utc = TimeZone(identifier: "UTC")!

/// One status per vocabulary key, with representative arguments.
private let samples: [Status] = VocabularyKey.allCases.compactMap { Status(key: $0) } + [
    .savedAt(Date(timeIntervalSince1970: 1_791_208_920)),
    .waitingFor(source: "Studio"),
    .bytesVerified(verified: 3_100_000_000, total: 5_200_000_000),
    .sendingTo(host: "api.example.com"),
    .notOnThisDevice(source: "Studio"),
    .indexingChapters(indexed: 12, total: 40),
    .indexingChapters(indexed: 0, total: 1),
    .indexingChapters(indexed: 1, total: 1),
    .endpoint(host: "api.example.com", kind: .hosted, model: nil),
    .endpoint(host: "studio.local", kind: .local, model: nil),
    .endpoint(host: "hermes.tail1234.ts.net", kind: .userManaged, model: nil),
    .endpoint(host: "api.example.com", kind: .hosted, model: "example-model-1"),
    .endpoint(host: "studio.local", kind: .local, model: "llama"),
    .endpoint(host: "hermes.tail1234.ts.net", kind: .userManaged, model: "m"),
]

@Suite("String Catalog vocabulary (plan 4.4.6, 4.4.9)")
struct VocabularyCatalogTests {
    @Test("Every status from the compiled String Catalog equals the vocabulary template", arguments: samples)
    func catalogMatchesTemplates(status: Status) {
        #expect(status.text(locale: posix, timeZone: utc) == status.englishText(locale: posix, timeZone: utc))
    }

    @Test("Plural and interpolation through the catalog")
    func examples() {
        #expect(Status.indexingChapters(indexed: 0, total: 1).text(locale: posix) == "Indexing 0 of 1 chapter")
        #expect(Status.indexingChapters(indexed: 12, total: 40).text(locale: posix) == "Indexing 12 of 40 chapters")
        #expect(Status.bytesVerified(verified: 3_100_000_000, total: 5_200_000_000).text(locale: posix)
            == "3.1 of 5.2 GB verified")
        #expect(Status.savedAt(Date(timeIntervalSince1970: 1_791_208_920))
            .text(locale: Locale(identifier: "en_GB"), timeZone: utc) == "Saved 14:02")
        #expect(Status.endpoint(host: "api.example.com", kind: .hosted, model: "example-model-1").text(locale: posix)
            == "api.example.com · hosted · example-model-1")
        #expect(Status.saving.text() == "Saving…")
    }

    @Test("Labels and formats come from the catalog")
    func labels() {
        for key in LabelKey.allCases { #expect(key.localized == key.text, "\(key)") }
        #expect(Durations.text(seconds: 75_480, locale: posix) == "20h 58m")
        #expect(Durations.left(seconds: 75_480, locale: posix) == "20h 58m left")
        #expect(Durations.left(seconds: 42, locale: posix) == "42s left")
    }

    @Test("Marker labels for capture kinds, including unknown kinds")
    func markerLabels() {
        #expect(Marker.label(for: Marker.resolve(captureKind: "text_quote")) == "Quote")
        #expect(Marker.label(for: Marker.resolve(captureKind: "podcast_clip")) == "podcast_clip")
        #expect(Marker.resolve(captureKind: "podcast_clip").marker == .pending)
    }
}
