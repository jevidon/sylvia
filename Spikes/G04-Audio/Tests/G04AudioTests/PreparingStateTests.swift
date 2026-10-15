import Foundation
import Testing
@testable import G04AudioKit

/// Review R3-01: opening a long native FLAC or Ogg file with precise timing takes time proportional to its length
/// (tens of seconds for 10 hours on the simulator). A slow open is `.preparing`, never a decode error, and has no
/// time limit; the user's play and pause during it are honoured when the member is ready. Fake engine whose open
/// the test completes by hand.
@Suite("Playback service: a slow open is preparing, not a failure (unit)")
@MainActor
struct PreparingStateTests {
    /// Lets the main actor run the other task until `condition` holds.
    func settle(_ condition: () -> Bool) async {
        for _ in 0..<10_000 where !condition() { await Task.yield() }
    }

    func harnessWithCheckpoint(atMember member: Int, ms: Int64) throws -> Harness {
        let store = InMemoryPositionStore()
        let h = try Harness(store: store)
        let point = AudioPoint(assetID: h.edition.ids[member], ms: ms)
        let g = try h.edition.timeline.globalMs(of: point)
        try store.save(PlaybackCheckpoint(editionID: h.edition.timeline.editionID, timelineRevision: h.edition.timeline.revision,
                                          last: point, lastGlobalMs: g, furthest: point, furthestGlobalMs: g, listenedMs: 0, reason: .periodic))
        h.engine.holdsOpening = true
        return h
    }

    @Test func aSlowOpenIsPreparingAndPlayStartsWhenTheMemberIsReady() async throws {
        let h = try harnessWithCheckpoint(atMember: 1, ms: 40_000)
        let point = AudioPoint(assetID: h.edition.ids[1], ms: 40_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        #expect(h.service.status == .preparing(memberIndex: 1))
        #expect(h.service.currentPoint == point)  // the position shown and saved is the resume point
        h.service.handleLifecycle(.didEnterBackground)
        #expect(h.memory.history.last?.last == point && h.memory.history.last?.reason == .lifecycle)
        // Play while it opens: remembered, nothing claimed, the session left alone (another app keeps playing).
        h.service.play()
        #expect(h.service.status == .preparing(memberIndex: 1))
        #expect(h.service.isPlayingOrStarting)
        #expect(h.session.activations == 0)
        #expect(!h.engine.isPlaying)
        // However long it takes (no time limit in the service), it ends ready, not failed.
        h.clock.advance(60)
        h.engine.finishOpening(.ready)
        await loading.value
        #expect(h.service.status == .playing)
        #expect(h.session.activations == 1)
        #expect(h.engine.isPlaying)
        #expect(h.service.currentPoint == point)
    }

    @Test func aPauseWhileOpeningCancelsTheWishToPlay() async throws {
        let h = try harnessWithCheckpoint(atMember: 0, ms: 20_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        h.service.togglePlayPause()  // play
        #expect(h.service.isPlayingOrStarting)
        h.service.togglePlayPause()  // pause
        #expect(!h.service.isPlayingOrStarting)
        #expect(h.memory.history.last?.reason == .pause)
        h.engine.finishOpening(.ready)
        await loading.value
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
        #expect(h.session.events.isEmpty)  // never activated, so nothing released either
    }

    @Test func onlyTheSystemsFailureIsADecodeError() async throws {
        let h = try harnessWithCheckpoint(atMember: 2, ms: 5_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        h.service.play()
        h.engine.finishOpening(.failed("The operation could not be completed"))
        await loading.value
        #expect(h.service.status == .failed(memberIndex: 2, .decodeError("The operation could not be completed")))
        #expect(!h.service.isPlayingOrStarting)
        #expect(h.session.activations == 0)
        #expect(!h.engine.isPlaying)
    }

    @Test func aSeekWhileOpeningReplacesTheOpenAndKeepsTheWishToPlay() async throws {
        let h = try harnessWithCheckpoint(atMember: 0, ms: 30_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        h.service.play()
        let seeking = Task { await h.service.seek(toGlobalMs: 100_000) }  // member 2, 40 s in
        await loading.value  // the load's open was superseded: it returns without touching the state
        #expect(h.service.status == .preparing(memberIndex: 1))
        #expect(h.engine.isOpening)
        h.engine.finishOpening(.ready)
        await seeking.value
        #expect(h.service.status == .playing)
        #expect(h.service.currentGlobalMs == 100_000)
        #expect(h.session.activations == 1)
        #expect(h.memory.history.last?.reason == .seek)
    }

    @Test func aPauseDuringACrossMemberSeekWhilePlayingStaysPausedAndReleasesTheSession() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(5)
        h.engine.holdsOpening = true
        let seeking = Task { await h.service.seek(toGlobalMs: 70_000) }
        await settle { h.engine.isOpening }
        #expect(h.service.status == .preparing(memberIndex: 1))
        #expect(h.service.isPlayingOrStarting)
        h.service.pause()
        #expect(h.session.events == ["activate", "deactivate"])
        h.engine.finishOpening(.ready)
        await seeking.value
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
        #expect(h.service.currentGlobalMs == 70_000)
    }

    @Test func aCrossMemberSeekWhilePlayingResumesWithoutReactivatingTheSession() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(5)
        h.engine.holdsOpening = true
        let seeking = Task { await h.service.seek(toGlobalMs: 70_000) }
        await settle { h.engine.isOpening }
        h.engine.finishOpening(.ready)
        await seeking.value
        #expect(h.service.status == .playing)
        #expect(h.engine.isPlaying)
        #expect(h.session.events == ["activate"])
    }

    @Test func anInterruptionWhileOpeningResumesOnlyWhenTheSystemSays() async throws {
        let h = try harnessWithCheckpoint(atMember: 1, ms: 10_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        h.service.play()
        h.service.interruptionBegan()
        #expect(!h.service.isPlayingOrStarting)
        h.service.interruptionEnded(shouldResume: true)
        #expect(h.service.isPlayingOrStarting)  // the user wanted to play when the interruption began
        h.engine.finishOpening(.ready)
        await loading.value
        #expect(h.service.status == .playing)
    }

    @Test func noPreviewWhileTheMainMemberOpens() async throws {
        let h = try harnessWithCheckpoint(atMember: 0, ms: 10_000)
        let loading = Task { await h.load() }
        await settle { h.engine.isOpening }
        #expect(await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a")) == false)
        #expect(h.service.mode == .main && h.preview.played.isEmpty)
        h.engine.finishOpening(.ready)
        await loading.value
        #expect(h.service.status == .paused)
    }
}
