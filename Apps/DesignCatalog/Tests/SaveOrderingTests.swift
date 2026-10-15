import Foundation
import SylviaDesign
import XCTest
@testable import DesignCatalog

/// The prototype's "Saved means written" rule (I-03, Section 11.1, ADR-0013 Section 11), checked on
/// the model and the store directly: the capture sheet says "Saved" only after `CaptureStore` has
/// written the record to disk, a failed write keeps the text and writes nothing, the player says
/// "Audio excerpt saved" only after the excerpt record is written, and an interrupted answer is
/// never marked complete (I-04). Each test uses its own temporary directory.
@MainActor
final class SaveOrderingTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("SaveOrderingTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func records(in store: CaptureStore) throws -> [CaptureStore.Record] {
        let data = try Data(contentsOf: store.url)
        return try JSONDecoder().decode([CaptureStore.Record].self, from: data)
    }

    /// Polls `condition` on the main actor until it holds or `seconds` pass.
    private func wait(seconds: Double = 10, until condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func testCommitWritesTheRecordBeforeReturning() async throws {
        let store = CaptureStore(directory: directory)
        let record = CaptureStore.Record(kind: "text_quote", text: "the roar", note: "a note")
        _ = try await store.commit(record, duration: .zero, fail: false)
        let written = try records(in: store)
        XCTAssertEqual(written.map(\.note), ["a note"])
        XCTAssertEqual(written.map(\.kind), ["text_quote"])
        let protection = try FileManager.default.attributesOfItem(atPath: store.url.path)[.protectionKey] as? FileProtectionType
        // Where the file system reports a protection class it must be the one requested. The
        // simulator does not enforce data protection, so this is not a device result.
        if let protection { XCTAssertEqual(protection, .completeUntilFirstUserAuthentication) }
    }

    func testFailedCommitWritesNothing() async throws {
        let store = CaptureStore(directory: directory)
        do {
            _ = try await store.commit(CaptureStore.Record(kind: "note", text: "", note: "x"), duration: .zero, fail: true)
            XCTFail("the commit should have thrown")
        } catch is CaptureStore.WriteFailed {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testSheetSaysSavedOnlyAfterTheWrite() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.5, store: store)
        model.openCapture(.quote)
        model.draft.note = "Total perception would destroy us."
        model.save()
        XCTAssertEqual(model.draft.saveState, .saving)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path), "nothing written yet")
        XCTAssertFalse(model.draft.canDismiss, "the sheet cannot be dismissed while the text is unsaved")
        var sawSavedBeforeFile = false
        await wait {
            if case .saved = model.draft.saveState, !FileManager.default.fileExists(atPath: store.url.path) {
                sawSavedBeforeFile = true
            }
            return model.draft.saveState != .saving
        }
        XCTAssertFalse(sawSavedBeforeFile, "Saved appeared before the record was on disk")
        guard case .saved = model.draft.saveState else {
            return XCTFail("expected Saved, got \(model.draft.saveState)")
        }
        XCTAssertEqual(try records(in: store).map(\.note), ["Total perception would destroy us."])
        XCTAssertTrue(model.draft.canDismiss)
        XCTAssertEqual(model.savedThoughts.first?.id, "saved-text_quote", "the thought is listed only after the write")
    }

    func testFailedSaveKeepsTheTextAndWritesNothing() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.05, store: store)
        model.openCapture(.quote)
        model.draft.note = "Keep me."
        model.nextSaveFails = true
        model.save()
        await wait { model.draft.saveState != .saving }
        XCTAssertEqual(model.draft.saveState, .failed)
        XCTAssertEqual(model.draft.note, "Keep me.")
        XCTAssertFalse(model.draft.canDismiss, "a failed save must not let the sheet close")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertTrue(model.savedThoughts.isEmpty)
        // The retry succeeds and only then says Saved.
        model.save()
        await wait { model.draft.saveState != .saving }
        guard case .saved = model.draft.saveState else { return XCTFail("retry: \(model.draft.saveState)") }
        XCTAssertEqual(try records(in: store).map(\.note), ["Keep me."])
    }

    func testExcerptSavedOnlyAfterTheExcerptRecordIsWritten() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.5, store: store)
        model.captureMoment()
        await wait { model.excerptPhase != .none }
        XCTAssertEqual(model.excerptPhase, .preserving, "the moment is kept first")
        XCTAssertEqual(try records(in: store).map(\.kind), ["audio_moment"], "the moment is on disk before preserving is shown")
        await wait { model.excerptPhase == .preserving ? false : true }
        XCTAssertEqual(model.excerptPhase, .saved)
        XCTAssertEqual(try records(in: store).map(\.kind), ["audio_moment", "audio_excerpt"])
    }

    func testFailedExcerptIsNotSaved() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.05, store: store)
        model.nextExcerptFails = true
        model.captureMoment()
        await wait { model.excerptPhase == .failed || model.excerptPhase == .saved }
        XCTAssertEqual(model.excerptPhase, .failed)
        XCTAssertEqual(try records(in: store).map(\.kind), ["audio_moment"], "the moment stays; no excerpt record")
    }

    /// Review R1-07: a failed moment write saves nothing, so neither "Moment saved · preserving
    /// audio" nor "Excerpt not preserved · Retry" (which says the bookmark survived) may show.
    func testFailedMomentWriteSavesNothing() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.05, store: store)
        model.nextMomentFails = true
        model.captureMoment()
        var seen: [PrototypeModel.ExcerptPhase] = []
        await wait {
            if seen.last != model.excerptPhase { seen.append(model.excerptPhase) }
            return model.excerptPhase != .none
        }
        try? await Task.sleep(for: .milliseconds(300))
        if seen.last != model.excerptPhase { seen.append(model.excerptPhase) }
        XCTAssertEqual(model.excerptPhase, .momentNotSaved)
        XCTAssertEqual(seen, [.none, .momentNotSaved], "no saved or preserving state was shown")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path), "nothing was written")
        // A retry goes through the whole path again and saves both records.
        model.captureMoment()
        await wait { model.excerptPhase == .saved || model.excerptPhase == .failed }
        XCTAssertEqual(model.excerptPhase, .saved)
        XCTAssertEqual(try records(in: store).map(\.kind), ["audio_moment", "audio_excerpt"])
    }

    /// Review R1-07: a record whose write fails is not kept in memory, so a later successful commit
    /// does not persist it.
    func testFailedDiskWriteLeavesNothingForTheNextCommit() async throws {
        let store = CaptureStore(directory: directory)
        // A directory where the JSON file belongs makes the atomic write fail.
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: true)
        let lost = CaptureStore.Record(kind: "text_quote", text: "the roar", note: "never written")
        do {
            _ = try await store.commit(lost, duration: .zero, fail: false)
            XCTFail("the write into a directory should fail")
        } catch {}
        try FileManager.default.removeItem(at: store.url)
        let kept = CaptureStore.Record(kind: "text_quote", text: "the roar", note: "written")
        _ = try await store.commit(kept, duration: .zero, fail: false)
        XCTAssertEqual(try records(in: store).map(\.note), ["written"], "the failed record must not reappear")
    }

    /// Review R1-07: the audio capture detail opened directly says "Audio excerpt saved" only after
    /// the moment and excerpt records are written.
    func testAudioCaptureScreenSavesThroughTheWrite() async throws {
        let store = CaptureStore(directory: directory)
        let model = PrototypeModel(writeSeconds: 0.05, store: store)
        model.open(.audioCapture)
        XCTAssertNotEqual(model.excerptPhase, .saved, "not saved before any write")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
        await wait { model.excerptPhase == .saved || model.excerptPhase == .failed }
        XCTAssertEqual(model.excerptPhase, .saved)
        XCTAssertEqual(try records(in: store).map(\.kind), ["audio_moment", "audio_excerpt"])
    }

    func testInterruptedAnswerIsNeverComplete() async throws {
        let model = PrototypeModel(writeSeconds: 0, store: CaptureStore(directory: directory))
        model.nextAnswerInterrupted = true
        model.send()
        XCTAssertEqual(model.askPhase, .sending)
        var sawComplete = false
        await wait(seconds: 15) {
            if case .answering(_, true) = model.askPhase { sawComplete = true }
            if case .interrupted = model.askPhase { return true }
            return false
        }
        XCTAssertFalse(sawComplete, "an interrupted answer was shown as complete")
        XCTAssertEqual(model.askPhase, .interrupted(received: 2))
    }

    func testStoppedAnswerKeepsWhatArrived() async throws {
        let model = PrototypeModel(writeSeconds: 0, store: CaptureStore(directory: directory))
        model.send()
        await wait(seconds: 15) { if case .answering(1, false) = model.askPhase { true } else { false } }
        model.stopAsking()
        XCTAssertEqual(model.askPhase, .interrupted(received: 1))
    }
}
