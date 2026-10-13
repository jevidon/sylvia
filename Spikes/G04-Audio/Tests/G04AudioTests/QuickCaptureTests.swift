import AppIntents
import Foundation
import MediaPlayer
import Testing
@testable import G04AudioHarness
@testable import G04AudioKit

/// A store that remembers the order of events, so a test can check that a save was durable before the
/// acknowledgement went out.
final class OrderedStore: CaptureStore, @unchecked Sendable {
    let inner: FileCaptureStore
    private let lock = NSLock()
    private(set) var events: [String] = []
    var failWrites = false
    init(_ inner: FileCaptureStore) { self.inner = inner }
    func note(_ e: String) { lock.withLock { events.append(e) } }
    func commit(_ record: CaptureRecord) throws {
        if failWrites { throw DurableFileError.write(path: "captures", errno: 28) }
        try inner.commit(record)
        note("durable:\(record.excerpt == .pending ? "pending" : "other")")
    }
    func insert(_ record: CaptureRecord) throws -> CaptureRecord {
        if failWrites { throw DurableFileError.write(path: "captures", errno: 28) }
        let stored = try inner.insert(record)
        note("durable:\(stored.excerpt == .pending ? "pending" : "other")")
        return stored
    }
    func record(_ id: UUID) throws -> CaptureRecord? { try inner.record(id) }
    func all() throws -> [CaptureRecord] { try inner.all() }
    func excerptURL(for id: UUID) -> URL { inner.excerptURL(for: id) }
}

/// Quick-capture prototypes (ADR-0007; T25): the App Intent behind the Control Center / Lock Screen control, the
/// Action button and App Shortcuts, and the MPRemoteCommandCenter bookmark command. These run in the harness
/// app's process (the hosted test process). What the system does with them on a locked device is a device item.
@Suite("Quick capture (App Intent and bookmark command; T25)", .serialized, .temporaryStores)
@MainActor
struct QuickCaptureTests {
    struct Rig {
        let playback: PlaybackService
        let engine: FakeEngine
        let store: OrderedStore
        let captures: CaptureService
        let coordinator: QuickCaptureCoordinator
        let edition: TestEdition
    }

    func rig(load: Bool = true, exporter: any ExcerptExporting = ScriptedExporter(), clock: ManualClock = ManualClock()) async throws -> Rig {
        let edition = try TestEdition()
        let engine = FakeEngine(durations: edition.engineDurations)
        let playback = PlaybackService(engine: engine, previewPlayer: FakePreview(), session: SpySession(), positions: InMemoryPositionStore(), clock: ManualClock(), fileExists: { _ in true })
        if load {
            await playback.load(timeline: edition.timeline, resolveFile: edition.resolver)
            await playback.seek(toGlobalMs: 75_000)
        }
        let store = OrderedStore(try temporaryStore())
        let captures = CaptureService(store: store, exporter: exporter, resolveSource: edition.resolver)
        return Rig(playback: playback, engine: engine, store: store, captures: captures,
                   coordinator: QuickCaptureCoordinator(playback: playback, captures: captures, clock: clock), edition: edition)
    }

    /// Installs the same bridge the app installs at launch, over the rig's services.
    func install(_ rig: Rig) {
        let store = rig.store
        QuickCaptureBridge.handler = { origin in
            let outcome = rig.coordinator.captureNow(origin: origin)
            let reply = HarnessModel.reply(outcome)
            store.note("reply:\(reply.acknowledged)")
            return reply
        }
    }

    @Test func intentMetadataAllowsBackgroundExecutionWithoutUnlock() {
        #expect(CaptureMomentIntent.authenticationPolicy == .alwaysAllowed)
        #expect(CaptureMomentIntent.supportedModes == .background)
        #expect(String(localized: CaptureMomentIntent.title) == "Capture the last 30 seconds")
        // AudioPlaybackIntent is the adoption that asks the system to perform the intent in the app's process.
        #expect((CaptureMomentIntent() as Any) is any AudioPlaybackIntent)
    }

    @Test func intentAcknowledgesOnlyAfterTheAnchorIsDurable() async throws {
        let r = try await rig()
        install(r)
        defer { QuickCaptureBridge.handler = nil }
        let result = try await CaptureMomentIntent().perform()
        _ = result
        // The durable commit of the anchor happened before the reply was produced.
        let events = r.store.events
        #expect(events.first == "durable:pending")
        #expect((events.firstIndex(of: "reply:true") ?? -1) > 0)
        let records = try FileCaptureStore(directory: r.store.inner.directory).all()
        #expect(records.count == 1)
        let rec = try #require(records.first)
        #expect(rec.kind == .audio)
        #expect(rec.origin == "intent@\(Bundle.main.bundleIdentifier ?? "-")")
        #expect(QuickCaptureBridge.lastPerformedIn == "com.jevidon.sylvia.spike.g04audio")
        // The preceding 30 s of the position (75 s global = member 2 at 15 s): two ordered file-local ranges.
        #expect(rec.ranges == [AudioRange(assetID: r.edition.ids[0], startMs: 45_000, endMs: 60_000),
                               AudioRange(assetID: r.edition.ids[1], startMs: 0, endMs: 15_000)])
        await r.coordinator.waitForExport(rec.id)
        #expect(try r.store.record(rec.id)?.statusKey == .audioExcerptSaved)
    }

    @Test func intentReplyUsesTheVocabularyPhrase() async throws {
        let r = try await rig()
        let outcome = r.coordinator.captureNow(origin: "test")
        let reply = HarnessModel.reply(outcome)
        #expect(reply == QuickCaptureReply(acknowledged: true, message: "Moment saved · preserving audio"))
    }

    @Test func intentFailsWithoutClaimingASaveWhenTheStoreFails() async throws {
        let r = try await rig()
        r.store.failWrites = true
        install(r)
        defer { QuickCaptureBridge.handler = nil }
        do {
            _ = try await CaptureMomentIntent(surface: .control).perform()
            Issue.record("perform succeeded although the store failed")
        } catch let e as QuickCaptureIntentError {
            // The system shows this text. A capture has no text, so it is the proposed key for "moment not saved",
            // never save.failed's "your text is still here" (review R2-04).
            guard case let .notSaved(message) = e else { Issue.record("wrong error \(e)"); return }
            #expect(message == "[audio.moment_not_saved]")
            #expect(String(localized: e.localizedStringResource) == "[audio.moment_not_saved]")
        }
        #expect(try r.store.inner.all().isEmpty)
        #expect(r.store.events == ["reply:false"])
    }

    /// Review R2-05: the control's intent records its surface, so the device run can tell a control press from the
    /// App Shortcut, Siri or the Shortcuts app, and the repeat window never merges two different surfaces.
    @Test func theControlRecordsItsSurfaceAndIsNotMergedWithOtherEntryPoints() async throws {
        let r = try await rig()
        install(r)
        defer { QuickCaptureBridge.handler = nil }
        let process = try #require(Bundle.main.bundleIdentifier)
        #expect(CaptureMomentIntent(surface: .control).surface == .control)
        #expect(CaptureMomentIntent().surface == nil)
        _ = try await CaptureMomentIntent(surface: .control).perform()
        _ = try await CaptureMomentIntent().perform()  // within the repeat window, same position, another entry point
        _ = try await CaptureMomentIntent(surface: .control).perform()  // a repeat of the control press: same capture
        let records = try r.store.inner.all()
        #expect(records.count == 2)
        #expect(Set(records.map(\.origin)) == ["intent.control@\(process)", "intent@\(process)"])
        for record in records { await r.coordinator.waitForExport(record.id) }
    }

    @Test func intentFailsWhenNothingIsLoaded() async throws {
        let r = try await rig(load: false)
        install(r)
        defer { QuickCaptureBridge.handler = nil }
        await #expect(throws: QuickCaptureIntentError.self) { try await CaptureMomentIntent().perform() }
        #expect(try r.store.inner.all().isEmpty)
    }

    /// In a process without the app's handler (the control extension, if the system ever ran it there), the intent
    /// refuses instead of claiming a save.
    @Test func intentRefusesOutsideTheAppProcess() async throws {
        QuickCaptureBridge.handler = nil
        do {
            _ = try await CaptureMomentIntent().perform()
            Issue.record("perform succeeded without a handler")
        } catch let e as QuickCaptureIntentError {
            guard case .notInAppProcess = e else { Issue.record("wrong error \(e)"); return }
        }
    }

    @Test func failedExportAfterAcknowledgementKeepsTheMomentAndOffersRetry() async throws {
        let r = try await rig(exporter: ScriptedExporter(failures: 1))
        install(r)
        defer { QuickCaptureBridge.handler = nil }
        _ = try await CaptureMomentIntent().perform()
        let rec = try #require(try r.store.all().first)
        await r.coordinator.waitForExport(rec.id)
        let after = try #require(try r.store.record(rec.id))
        #expect(after.statusKey == .audioExcerptNotPreserved)
        #expect(after.ranges == rec.ranges)
        #expect(SpikePhrases.phrase(after.statusKey) == "Excerpt not preserved · Retry")
    }

    /// Review R1-12: App Intents carry no delivery identity, so a re-delivered intent (or a double press) must not
    /// create a second capture. Within the repeat window, from the same surface and about the same position, the
    /// coordinator reuses the first request's idempotency key and the store returns the existing record.
    @Test func aRepeatedRequestFromTheSameSurfaceReturnsTheSameCapture() async throws {
        let clock = ManualClock()
        let r = try await rig(clock: clock)
        func capture(_ origin: String) throws -> CaptureRecord {
            guard case let .saved(record) = r.coordinator.captureNow(origin: origin) else {
                throw ExportError.emptyOutput
            }
            return record
        }
        let first = try capture("intent@app")
        clock.advance(QuickCaptureCoordinator.repeatWindowSeconds - 0.5)
        let again = try capture("intent@app")
        #expect(again.id == first.id)
        #expect(try r.store.inner.all().count == 1)
        let other = try capture("player")  // another surface is another capture
        #expect(other.id != first.id)
        clock.advance(1)  // outside the window of the first request
        let later = try capture("intent@app")
        #expect(later.id != first.id)
        await r.playback.seek(toGlobalMs: 150_000)  // inside the window, but far from the last position
        let elsewhere = try capture("intent@app")
        #expect(elsewhere.id != later.id)
        #expect(try r.store.inner.all().count == 4)
        #expect(r.coordinator.saveDurations.count == 4)  // the repeat was answered, not saved again
        for record in try r.store.inner.all() { await r.coordinator.waitForExport(record.id) }
    }

    /// Review R3-04: the in-player Capture button passes its own key per tap (as the harness's button does), so two
    /// quick taps at the same place are two captures with two exports; the repeat window applies only to callers
    /// without a request identity. A re-sent request with the same key is still answered with the same record.
    @Test func inPlayerTapsEachMakeACaptureEvenWithinTheRepeatWindow() async throws {
        let clock = ManualClock()
        let r = try await rig(clock: clock)
        func tap(_ key: String) throws -> CaptureRecord {
            guard case let .saved(record) = r.coordinator.captureNow(origin: "player", idempotencyKey: key) else {
                throw ExportError.emptyOutput
            }
            return record
        }
        let firstKey = QuickCaptureCoordinator.requestKey(origin: "player")
        let first = try tap(firstKey)
        clock.advance(0.5)  // well inside the 2 s window, same position (playback is paused)
        let second = try tap(QuickCaptureCoordinator.requestKey(origin: "player"))
        #expect(second.id != first.id)
        #expect(second.ranges == first.ranges)
        #expect(r.coordinator.saveDurations.count == 2)
        #expect(try tap(firstKey).id == first.id)  // the same request re-sent: the same record
        #expect(try r.store.inner.all().count == 2)
        for record in try r.store.inner.all() {
            await r.coordinator.waitForExport(record.id)
            #expect(try r.store.inner.record(record.id)?.statusKey == .audioExcerptSaved)
        }
    }

    /// Review R1-05: at launch the coordinator resumes exports an earlier process left pending.
    @Test func launchResumesExportsLeftPendingByAnEarlierProcess() async throws {
        let r = try await rig()
        let earlier = CaptureService(store: r.store, exporter: GatedExporter(), resolveSource: r.edition.resolver)
        let record = try earlier.captureAudio(timeline: r.edition.timeline, atGlobalMs: 75_000, note: "kept",
                                              idempotencyKey: "earlier-process", origin: "intent@app")
        #expect(record.statusKey == .audioMomentSaved)
        let resumed = await r.coordinator.resumeInterruptedExports()
        #expect(resumed == [record.id])
        #expect(r.coordinator.isExporting(record.id))
        await r.coordinator.waitForExport(record.id)
        let after = try #require(try r.store.record(record.id))
        #expect(after.statusKey == .audioExcerptSaved)
        #expect(after.note == "kept")
        #expect(!r.coordinator.isExporting(record.id))
        #expect(await r.coordinator.resumeInterruptedExports().isEmpty)
    }

    /// The bookmark remote command (MPRemoteCommandCenter.bookmarkCommand) is registered only on request, is
    /// separate from play/pause/skip, and its handler saves durably through the same coordinator.
    @Test func bookmarkCommandIsOptInAndSavesThroughTheCoordinator() async throws {
        let r = try await rig()
        let nowPlaying = NowPlayingController(service: r.playback)
        defer { nowPlaying.unregister() }
        let registered = nowPlaying.register()
        #expect(!registered.contains("bookmark"))
        #expect(!nowPlaying.isEnabled("bookmark"))
        let store = r.store
        nowPlaying.enableBookmarkCapture {
            let reply = HarnessModel.reply(r.coordinator.captureNow(origin: "remote-bookmark-command"))
            store.note("reply:\(reply.acknowledged)")
            return reply.acknowledged
        }
        #expect(nowPlaying.isEnabled("bookmark"))
        #expect(MPRemoteCommandCenter.shared().bookmarkCommand.isEnabled)
        // Play, pause and skip keep their meanings: none of them captures.
        for command: NowPlayingController.Command in [.togglePlayPause, .togglePlayPause, .skipForward, .skipBackward] {
            _ = await nowPlaying.perform(command)
        }
        #expect(try r.store.all().isEmpty)
        let before = r.playback.currentGlobalMs
        // The synchronous handler path the registered target runs: success only after the durable write.
        let status = nowPlaying.performBookmark()
        #expect(status == .success)
        #expect(r.store.events == ["durable:pending", "reply:true"])
        #expect(try r.store.all().count == 1)
        // Transport is untouched by a capture.
        #expect(r.playback.currentGlobalMs == before)
        #expect(r.playback.status == .paused)
    }

    @Test func bookmarkCommandReportsFailureWhenTheSaveFails() async throws {
        let r = try await rig()
        let nowPlaying = NowPlayingController(service: r.playback)
        defer { nowPlaying.unregister() }
        nowPlaying.register()
        nowPlaying.enableBookmarkCapture { HarnessModel.reply(r.coordinator.captureNow(origin: "remote-bookmark-command")).acknowledged }
        r.store.failWrites = true
        #expect(nowPlaying.performBookmark() == .commandFailed)
        #expect(try r.store.inner.all().isEmpty)
    }
}
