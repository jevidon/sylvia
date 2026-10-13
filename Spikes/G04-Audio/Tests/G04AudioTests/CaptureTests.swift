import Foundation
import Testing
@testable import G04AudioKit

/// An exporter that fails or succeeds on demand and records calls.
final class ScriptedExporter: ExcerptExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresLeft: Int
    private(set) var calls: [[SourceSegment]] = []
    init(failures: Int = 0) { failuresLeft = failures }
    func export(_ segments: [SourceSegment], to url: URL) async throws -> ExportedExcerpt {
        let fail = lock.withLock { () -> Bool in
            calls.append(segments)
            if failuresLeft > 0 { failuresLeft -= 1; return true }
            return false
        }
        if fail { throw ExportError.encodeFailed("scripted failure") }
        try Data([0]).write(to: url)
        return ExportedExcerpt(fileName: url.lastPathComponent, format: "test", sourceFormats: segments.map { _ in "test" }, requestedRanges: segments.map(\.range),
                               actualRanges: segments.map(\.range), frameCount: 1, sampleRate: 44_100, outputDurationMs: 0, byteCount: 1)
    }
}

/// An exporter whose calls block until the test releases them, so a test can act while an export is running.
final class GatedExporter: ExcerptExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var calls: [[SourceSegment]] = []
    var callCount: Int { lock.withLock { calls.count } }

    func export(_ segments: [SourceSegment], to url: URL) async throws -> ExportedExcerpt {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            lock.withLock {
                calls.append(segments)
                waiting.append(c)
            }
        }
        try Data([0]).write(to: url)
        return ExportedExcerpt(fileName: url.lastPathComponent, format: "test", sourceFormats: segments.map { _ in "test" }, requestedRanges: segments.map(\.range),
                               actualRanges: segments.map(\.range), frameCount: 1, sampleRate: 44_100, outputDurationMs: 0, byteCount: 1)
    }

    /// Resumes every export that is waiting now.
    func releaseAll() {
        let resume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { waiting.removeAll() }
            return waiting
        }
        resume.forEach { $0.resume() }
    }

    /// Waits (polling, up to 5 s) until `n` exports have started.
    func waitForCalls(_ n: Int) async {
        for _ in 0..<500 where callCount < n { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

/// A store whose writes can be made to fail (disk full).
final class FlakyStore: CaptureStore, @unchecked Sendable {
    let inner: FileCaptureStore
    var failWrites = false
    init(_ inner: FileCaptureStore) { self.inner = inner }
    func commit(_ record: CaptureRecord) throws {
        if failWrites { throw DurableFileError.write(path: "captures", errno: 28) }
        try inner.commit(record)
    }
    func insert(_ record: CaptureRecord) throws -> CaptureRecord {
        if failWrites { throw DurableFileError.write(path: "captures", errno: 28) }
        return try inner.insert(record)
    }
    func record(_ id: UUID) throws -> CaptureRecord? { try inner.record(id) }
    func all() throws -> [CaptureRecord] { try inner.all() }
    func excerptURL(for id: UUID) -> URL { inner.excerptURL(for: id) }
}

/// A capture store in a directory owned by the running test. Every suite that calls this carries the
/// `.temporaryStores` trait, which gives each test its own parent directory and removes it (stores and excerpts)
/// when the test ends. Outside that scope the call fails rather than leaking files.
func temporaryStore() throws -> FileCaptureStore {
    guard let root = TemporaryStores.root else {
        struct NoScope: Error, CustomStringConvertible { var description: String { "temporaryStore() needs the .temporaryStores trait" } }
        throw NoScope()
    }
    return try FileCaptureStore(directory: root.appendingPathComponent("store-\(UUID().uuidString)"))
}

/// Gives each test a temporary directory for its capture stores and deletes it afterwards (review R1-12).
struct TemporaryStores: TestTrait, SuiteTrait, TestScoping {
    @TaskLocal static var root: URL?

    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        // Suites get a scope too; only test functions (and their cases) need a directory.
        guard test.isSuite == false else { try await function(); return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-captures-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await Self.$root.withValue(dir) { try await function() }
    }
}

extension Trait where Self == TemporaryStores {
    static var temporaryStores: TemporaryStores { TemporaryStores() }
}

@Suite("Capture semantics (unit; plan 10.2, 11.1, 18.3; T21, T23)", .temporaryStores)
struct CaptureTests {
    let edition = try! EditionTimeline(editionID: UUID(), members: [
        EditionMember(assetID: UUID(), fileName: "a.mp3", durationMs: 100_000),
        EditionMember(assetID: UUID(), fileName: "b.mp3", durationMs: 100_000),
    ])

    func service(_ store: any CaptureStore, _ exporter: any ExcerptExporting, available: Bool = true) -> CaptureService {
        CaptureService(store: store, exporter: exporter, resolveSource: { _ in available ? URL(fileURLWithPath: "/fake.mp3") : nil })
    }

    @Test func bookmarkIsAPositionOnlyAndDurableBeforeItReturns() async throws {
        let store = try temporaryStore()
        let s = service(store, ScriptedExporter())
        let r = try s.bookmark(timeline: edition, atGlobalMs: 150_000, note: "my note", idempotencyKey: "k1")
        #expect(r.kind == .bookmark)
        #expect(r.point == AudioPoint(assetID: edition.members[1].assetID, ms: 50_000))
        #expect(r.ranges.isEmpty)
        #expect(r.statusKey == .saveDone)
        // Durable: a fresh store over the same directory reads it back.
        let reread = try FileCaptureStore(directory: store.directory).record(r.id)
        #expect(reread == r)
    }

    @Test func audioCaptureWritesAnchorAndNoteBeforeTheExcerpt() async throws {
        let store = try temporaryStore()
        let exporter = ScriptedExporter()
        let s = service(store, exporter)
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 115_000, note: "cross-file", idempotencyKey: "k2")
        // Preceding 30 s across the file boundary: two ordered file-local ranges.
        #expect(r.ranges == [
            AudioRange(assetID: edition.members[0].assetID, startMs: 85_000, endMs: 100_000),
            AudioRange(assetID: edition.members[1].assetID, startMs: 0, endMs: 15_000),
        ])
        #expect(r.excerpt == .pending)
        #expect(r.statusKey == .audioMomentSaved)
        #expect(exporter.calls.isEmpty)
        #expect(try store.record(r.id) == r)  // durable before any export
        let done = try await s.preserveExcerpt(r.id)
        #expect(done.statusKey == .audioExcerptSaved)
        #expect(done.note == "cross-file")
        #expect(exporter.calls.count == 1)
        #expect(exporter.calls[0].map(\.range) == r.ranges)
        if case let .saved(e) = done.excerpt { #expect(e.actualRanges == r.ranges) } else { Issue.record("not saved") }
        #expect(try store.record(r.id) == done)
    }

    @Test func failedExportKeepsBookmarkAndNoteAndOffersRetry() async throws {
        let store = try temporaryStore()
        let s = service(store, ScriptedExporter(failures: 1))
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: "keep me", idempotencyKey: "k3")
        let failed = try await s.preserveExcerpt(r.id)
        #expect(failed.statusKey == .audioExcerptNotPreserved)
        #expect(failed.canRetryExport)
        #expect(failed.note == "keep me")
        #expect(failed.ranges == r.ranges)
        #expect(try store.record(r.id)?.statusKey == .audioExcerptNotPreserved)
        #expect(!FileManager.default.fileExists(atPath: store.excerptURL(for: r.id).path))
        let retried = try await s.retry(r.id)
        #expect(retried.statusKey == .audioExcerptSaved)
    }

    @Test func missingSourceFailsHonestlyAndRetrySucceedsWhenItReturns() async throws {
        let store = try temporaryStore()
        let exporter = ScriptedExporter()
        let away = service(store, exporter, available: false)
        let r = try away.captureAudio(timeline: edition, atGlobalMs: 40_000, note: nil, idempotencyKey: "k4")
        let failed = try await away.preserveExcerpt(r.id)
        #expect(failed.excerpt == .failed(reason: "source not on this device", attempts: 1))
        #expect(exporter.calls.isEmpty)
        let back = service(store, exporter)
        #expect(try await back.retry(r.id).statusKey == .audioExcerptSaved)
    }

    @Test func storeFailureMeansNotSavedAndNothingWritten() async throws {
        let inner = try temporaryStore()
        let store = FlakyStore(inner)
        store.failWrites = true
        let s = service(store, ScriptedExporter())
        #expect(throws: CaptureError.self) {
            try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: "draft", idempotencyKey: "k5")
        }
        #expect(try inner.all().isEmpty)
    }

    @Test func idempotencyKeyNeverDuplicatesACapture() async throws {
        let store = try temporaryStore()
        let s = service(store, ScriptedExporter())
        let a = try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: nil, idempotencyKey: "same")
        let b = try s.captureAudio(timeline: edition, atGlobalMs: 90_000, note: nil, idempotencyKey: "same")
        #expect(a == b)
        #expect(try store.all().count == 1)
    }

    @Test func defaultRangeIsClampedAtTheEditionBounds() {
        #expect(CaptureRange.preceding(globalMs: 12_000, durationMs: 200_000) == (0, 12_000))
        #expect(CaptureRange.preceding(globalMs: 400, durationMs: 200_000) == (0, 1_000))
        #expect(CaptureRange.preceding(globalMs: 0, durationMs: 200_000) == (0, 1_000))
        #expect(CaptureRange.preceding(globalMs: 250_000, durationMs: 200_000) == (170_000, 200_000))
        #expect(CaptureRange.preceding(globalMs: 77_777, durationMs: 200_000) == (47_777, 77_777))
    }

    @Test func numericStartEndControlsEnforceTheLimits() async throws {
        let store = try temporaryStore()
        let s = service(store, ScriptedExporter())
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 60_000, note: nil, idempotencyKey: "k6")
        let extended = try await s.setRange(r.id, timeline: edition, globalStartMs: 40_000, globalEndMs: 160_000)  // 120 s, two files
        #expect(extended.ranges.count == 2)
        #expect(extended.ranges.reduce(0) { $0 + $1.durationMs } == 120_000)
        #expect(extended.excerpt == .pending)
        await #expect(throws: CaptureError.range(.tooLong(120_001))) {
            try await s.setRange(r.id, timeline: edition, globalStartMs: 40_000, globalEndMs: 160_001)
        }
        await #expect(throws: CaptureError.range(.tooShort(999))) {
            try await s.setRange(r.id, timeline: edition, globalStartMs: 40_000, globalEndMs: 40_999)
        }
        await #expect(throws: CaptureError.range(.startAfterEnd)) {
            try await s.setRange(r.id, timeline: edition, globalStartMs: 50_000, globalEndMs: 40_000)
        }
        await #expect(throws: CaptureError.range(.outOfBounds)) {
            try await s.setRange(r.id, timeline: edition, globalStartMs: 150_000, globalEndMs: 200_001)
        }
        let trimmed = try await s.setRange(r.id, timeline: edition, globalStartMs: 55_000, globalEndMs: 58_500)
        #expect(trimmed.ranges == [AudioRange(assetID: edition.members[0].assetID, startMs: 55_000, endMs: 58_500)])
        let b = try s.bookmark(timeline: edition, atGlobalMs: 1, note: nil, idempotencyKey: "bm")
        await #expect(throws: CaptureError.notAnAudioCapture) {
            try await s.setRange(b.id, timeline: edition, globalStartMs: 0, globalEndMs: 5_000)
        }
    }

    @Test func concurrentExportRequestsForOneCaptureRunOneExport() async throws {
        let store = try temporaryStore()
        let exporter = GatedExporter()
        let s = service(store, exporter)
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: nil, idempotencyKey: "c1")
        async let first = s.preserveExcerpt(r.id)
        await exporter.waitForCalls(1)
        async let second = s.preserveExcerpt(r.id)  // waits for the running export, then finds it saved
        try await Task.sleep(for: .milliseconds(50))
        #expect(exporter.callCount == 1)
        exporter.releaseAll()
        let (a, b) = try await (first, second)
        #expect(a.statusKey == .audioExcerptSaved && b.statusKey == .audioExcerptSaved)
        #expect(exporter.callCount == 1)
    }

    @Test func aRangeChangedDuringAnExportIsExportedAfterItAndTheStaleResultIsDropped() async throws {
        let store = try temporaryStore()
        let exporter = GatedExporter()
        let s = service(store, exporter)
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: nil, idempotencyKey: "c2")
        async let stale = s.preserveExcerpt(r.id)
        await exporter.waitForCalls(1)
        // The user edits the range with the numeric controls while the first export runs.
        let edited = try await s.setRange(r.id, timeline: edition, globalStartMs: 20_000, globalEndMs: 45_000)
        async let fresh = s.preserveExcerpt(r.id)
        exporter.releaseAll()
        let staleResult = try await stale
        #expect(staleResult.excerpt == .pending, "the stale export must not mark the edited capture saved")
        await exporter.waitForCalls(2)
        exporter.releaseAll()
        let done = try await fresh
        #expect(done.ranges == edited.ranges)
        guard case let .saved(e) = done.excerpt else { Issue.record("not saved: \(done.excerpt)"); return }
        #expect(e.requestedRanges == edited.ranges)
        #expect(exporter.calls.map { $0.map(\.range) } == [r.ranges, edited.ranges])
        #expect(try store.record(r.id) == done)
    }

    @Test func T23_sourceRemovalIsGuardedWhileAnExcerptIsPendingOrFailed() async throws {
        let store = try temporaryStore()
        let s = service(store, ScriptedExporter(failures: 1))
        let a = edition.members[0].assetID
        let pending = try s.captureAudio(timeline: edition, atGlobalMs: 30_000, note: nil, idempotencyKey: "p")
        var impact = try await s.sourceRemovalImpact(assetID: a)
        #expect(impact.requiresExplicitChoice)
        #expect(impact.unpreservedCaptures == [pending.id])
        _ = try await s.preserveExcerpt(pending.id)  // fails (scripted)
        impact = try await s.sourceRemovalImpact(assetID: a)
        #expect(impact.unpreservedCaptures == [pending.id])
        _ = try await s.retry(pending.id)
        impact = try await s.sourceRemovalImpact(assetID: a)
        #expect(!impact.requiresExplicitChoice)
        #expect(impact.preservedCaptures == [pending.id])
        #expect(try await s.sourceRemovalImpact(assetID: edition.members[1].assetID) == SourceRemovalImpact(unpreservedCaptures: [], preservedCaptures: []))
    }

    /// Review R1-05: a capture whose export never finished because the process ended stays pending on disk. The next
    /// process finds it, offers Retry for it, and resumes its export; nothing stays "preserving audio" forever.
    @Test func exportsInterruptedByTerminationAreFoundRetriedAndResumed() async throws {
        let store = try temporaryStore()
        // Process 1: the anchor and note are durable, then the process ends before the export result is written.
        let first = service(store, GatedExporter())
        let a = try first.captureAudio(timeline: edition, atGlobalMs: 40_000, note: "a", idempotencyKey: "i1")
        let b = try first.captureAudio(timeline: edition, atGlobalMs: 150_000, note: "b", idempotencyKey: "i2")
        let done = try first.bookmark(timeline: edition, atGlobalMs: 5_000, note: nil, idempotencyKey: "i3")
        #expect(try store.record(a.id)?.statusKey == .audioMomentSaved)

        // Process 2 over the same directory: both pending captures are interrupted, the bookmark is not.
        let reopened = try FileCaptureStore(directory: store.directory)
        let exporter = ScriptedExporter(failures: 1)
        let second = service(reopened, exporter)
        let interrupted = try await second.interruptedExports()
        #expect(Set(interrupted) == [a.id, b.id])
        #expect(!interrupted.contains(done.id))
        let stale = try #require(try reopened.record(a.id))
        #expect(await second.canRetry(stale), "a stale pending capture must offer Retry")
        // Resuming: the first export fails (Retry offered, note and ranges kept), the second succeeds.
        let resultA = try await second.preserveExcerpt(a.id)
        #expect(resultA.statusKey == .audioExcerptNotPreserved && resultA.note == "a" && resultA.ranges == a.ranges)
        let resultB = try await second.retry(b.id)  // Retry on a stale pending capture runs the export
        #expect(resultB.statusKey == .audioExcerptSaved && resultB.note == "b")
        #expect(try await second.interruptedExports().isEmpty)
        #expect(try await second.retry(a.id).statusKey == .audioExcerptSaved)
        #expect(exporter.calls.count == 3)
    }

    @Test func aPendingCaptureWithARunningExportIsNotRetriedOrResumed() async throws {
        let store = try temporaryStore()
        let exporter = GatedExporter()
        let s = service(store, exporter)
        let r = try s.captureAudio(timeline: edition, atGlobalMs: 40_000, note: nil, idempotencyKey: "run")
        async let running = s.preserveExcerpt(r.id)
        await exporter.waitForCalls(1)
        #expect(await s.isExportRunning(r.id))
        #expect(try await s.interruptedExports().isEmpty)
        #expect(await s.canRetry(try #require(try store.record(r.id))) == false)
        #expect(try await s.retry(r.id).excerpt == .pending)  // no second export
        exporter.releaseAll()
        #expect(try await running.statusKey == .audioExcerptSaved)
        #expect(exporter.callCount == 1)
    }

    // MARK: Vocabulary (plan 4.4.6; T54 for this moment)

    @Test func statusKeysMapToThePlanPhrasesVerbatim() {
        #expect(SpikePhrases.phrase(.audioMomentSaved) == "Moment saved · preserving audio")
        #expect(SpikePhrases.phrase(.audioExcerptSaved) == "Audio excerpt saved")
        #expect(SpikePhrases.phrase(.audioExcerptNotPreserved) == "Excerpt not preserved · Retry")
        #expect(SpikePhrases.phrase(.saveDone) == "Saved")
        #expect(SpikePhrases.phrase(.saveInProgress) == "Saving…")
        #expect(SpikePhrases.phrase(.saveFailed) == "Not saved · your text is still here")
        let forbidden = ["Clip saved", "Done", "Success", "Transcript"]
        // The keys are the design package's keys (G0.6 branch), not spike inventions.
        #expect(Set(VocabularyKey.allCases.map(\.rawValue)) == ["save.in_progress", "save.done", "save.failed",
                                                               "audio.moment_saved", "audio.excerpt_saved", "audio.excerpt_not_preserved"])
        for key in VocabularyKey.allCases {
            for f in forbidden { #expect(!SpikePhrases.phrase(key).contains(f)) }
        }
        // A proposed key has no phrase of its own: the harness shows the key.
        #expect(SpikePhrases.phrase(ProposedVocabularyKey.audioNothingToCapture) == "[audio.nothing_to_capture]")
        #expect(SpikePhrases.phrase(ProposedVocabularyKey.audioMomentNotSaved) == "[audio.moment_not_saved]")
        #expect(Set(ProposedVocabularyKey.allCases.map(\.rawValue)) == ["audio.nothing_to_capture", "audio.moment_not_saved"])
        let states: [ExcerptState] = [.notRequested, .pending, .failed(reason: "x", attempts: 1)]
        let base = CaptureRecord(id: UUID(), idempotencyKey: "", kind: .audio, editionID: UUID(), timelineRevision: 1, point: nil,
                                 ranges: [], note: nil, excerpt: .pending, createdAtMs: 0, updatedAtMs: 0, origin: "t")
        let keys: [VocabularyKey] = states.map { var r = base; r.excerpt = $0; return r.statusKey }
        #expect(keys == [VocabularyKey.saveDone, .audioMomentSaved, .audioExcerptNotPreserved])
    }

    @Test func audioCaptureRecordCarriesNoQuotedText() throws {
        let r = CaptureRecord(id: UUID(), idempotencyKey: "", kind: .audio, editionID: UUID(), timelineRevision: 1, point: nil,
                              ranges: [], note: nil, excerpt: .pending, createdAtMs: 0, updatedAtMs: 0, origin: "t")
        let json = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        #expect(!json.contains("quoted_text") && !json.contains("quotedText") && !json.contains("transcript"))
    }
}
