import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// Playback service logic over a deterministic engine and an injectable clock (plan 10.1, 10.3, 19.2; T18-T20, T22).
@Suite("Playback service (unit, fake engine and clock)")
@MainActor
struct PlaybackServiceTests {
    // MARK: Session

    @Test func audioSessionIsActivatedOnlyByPlay() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 30_000)
        h.service.setRate(2)
        await h.service.nextChapter()
        h.service.handleLifecycle(.didEnterBackground)
        #expect(h.session.activations == 0)
        h.service.play()
        #expect(h.session.activations == 1)
        #expect(h.service.status == .playing)
    }

    @Test func failedSessionActivationDoesNotClaimPlaying() async throws {
        let h = try Harness()
        await h.load()
        h.session.failNext = true
        h.service.play()
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
        h.service.pause()
        #expect(h.session.deactivations == 0)  // never activated, so nothing to release
    }

    /// Review R2-06: the session is released (with notifyOthersOnDeactivation) when playback stops for good, so an
    /// app that playback interrupted may resume; never after an interruption or a lost output device.
    @Test func userPauseReleasesTheSessionAndInterruptionsAndRouteLossDoNot() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        h.service.play()
        h.run(3)
        h.service.pause()
        #expect(h.session.events == ["activate", "deactivate"])
        h.service.pause()  // already released: nothing more
        #expect(h.session.deactivations == 1)
        // An interruption: the system deactivates the session; the service does not, and resumes when told to.
        h.service.play()
        h.run(3)
        postInterruption(center, began: true)
        #expect(h.service.status == .paused)
        #expect(h.session.deactivations == 1)
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .playing)
        #expect(h.session.activations == 3)
        // Headphones removed: paused, the session kept, so no other app starts on the speaker.
        h.run(3)
        postRoute(center, .oldDeviceUnavailable)
        #expect(h.service.status == .paused)
        #expect(h.session.deactivations == 1)
        #expect(h.session.isActive)
        // The user's own pause afterwards releases it.
        h.service.pause()
        #expect(h.session.deactivations == 2)
        #expect(!h.session.isActive)
        #expect(o.log.interruptionsBegan == 1)
    }

    @Test func aFailedDeactivationIsReportedAndTheNextPlayActivatesAgain() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(2)
        h.session.failNextDeactivation = true
        h.service.pause()
        #expect(h.service.lastSessionError != nil)
        #expect(h.service.status == .paused)
        h.service.play()
        #expect(h.service.status == .playing)
        #expect(h.session.activations == 2)
        h.service.pause()
        #expect(h.service.lastSessionError == nil)
        #expect(h.session.deactivations == 1)
    }

    @Test func theEndOfTheEditionAndABlockedSegmentReleaseTheSession() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 175_000)
        h.service.play()
        h.run(10)  // plays to the end of the 180 s edition
        #expect(h.service.status == .paused)
        #expect(h.session.events == ["activate", "deactivate"])
        let b = try Harness(missing: [1])
        await b.load()
        await b.service.seek(toGlobalMs: 58_000)
        b.service.play()
        b.run(5)
        #expect(b.service.status == .segmentUnavailable(memberIndex: 1))
        #expect(b.session.events == ["activate", "deactivate"])
        // A seek from playback into the blocked segment releases it too.
        await b.service.seek(toGlobalMs: 10_000)
        b.service.play()
        b.run(2)
        await b.service.seek(toGlobalMs: 100_000)
        #expect(b.service.status == .segmentUnavailable(memberIndex: 1))
        #expect(b.session.events == ["activate", "deactivate", "activate", "deactivate"])
    }

    @Test func previewReleasesTheSessionOnlyWhenMainDoesNotResume() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        let excerpt = URL(fileURLWithPath: "/fake/excerpt.m4a")
        // Main paused: the preview activates the session, its normal end releases it.
        #expect(await h.service.beginPreview(url: excerpt))
        #expect(h.session.events == ["activate"])
        h.preview.finish()
        #expect(h.session.events == ["activate", "deactivate"])
        // Main playing: main resumes after the preview, so the session is kept.
        h.service.play()
        h.run(2)
        #expect(await h.service.beginPreview(url: excerpt))
        h.preview.finish()
        #expect(h.service.status == .playing)
        #expect(h.session.isActive)
        #expect(h.session.deactivations == 1)
        // An interruption during preview: the system released the session; main stays paused; nothing to release.
        #expect(await h.service.beginPreview(url: excerpt))
        postInterruption(center, began: true)
        #expect(h.service.mode == .main && h.service.status == .paused)
        #expect(h.session.deactivations == 1)
        h.service.pause()
        #expect(h.session.deactivations == 1)
        // Headphones removed during a preview: main stays paused and the session is kept.
        #expect(await h.service.beginPreview(url: excerpt))
        postRoute(center, .oldDeviceUnavailable)
        #expect(h.service.mode == .main && h.service.status == .paused)
        #expect(h.session.isActive)
        #expect(o.log.interruptionsBegan == 1 && o.log.routeChanges.count == 1)
    }

    // MARK: Checkpoints (plan 10.1, 19.2: at most 5 s lost)

    @Test func checkpointsOnEveryBoundaryEvent() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(12)
        h.service.pause()
        await h.service.seek(toGlobalMs: 40_000)
        h.service.play()
        h.run(25)  // crosses into member 2 at 60 s
        h.service.interruptionBegan()
        h.service.handleLifecycle(.willResignActive)
        let reasons = Set(h.memory.history.map(\.reason))
        #expect(reasons.isSuperset(of: [.periodic, .pause, .seek, .itemChange, .interruption, .lifecycle]))
        let last = try #require(h.memory.history.last)
        #expect(last.last.assetID == h.edition.ids[1])
        #expect(abs(last.lastGlobalMs - 65_000) <= 60)
    }

    @Test("Crash loss stays within 4.5 s of media at every rate (random sessions; budget 5 s)", arguments: [Float(0.5), 1, 2, 3])
    func crashLossWithinFiveSeconds(rate: Float) async throws {
        var rng = SeededRNG(seed: UInt64(rate * 100))
        for _ in 0..<20 {
            let h = try Harness()
            await h.load()
            h.service.setRate(rate)
            h.service.play()
            for _ in 0..<40 {
                switch rng.next() % 10 {
                case 0: h.service.pause()
                case 1: h.service.play()
                case 2: await h.service.seek(toGlobalMs: Int64(rng.next() % 170_000))
                default: h.run(Double(rng.next() % 300) / 37)
                }
                // A crash now loses whatever was not checkpointed: under 4.5 s of media with ticks every 0.5 s (a
                // checkpoint 4 s of media after the last, at the next tick; ADR-0006 decision 8), inside the 5 s budget.
                guard let saved = h.memory.history.last else { continue }
                let truth = h.service.currentGlobalMs
                #expect(abs(truth - saved.lastGlobalMs) <= 4_500, "lost \(truth - saved.lastGlobalMs) ms at rate \(rate)")
            }
        }
    }

    /// At 3x five wall seconds would be 15 s of book, so the media rule decides: a checkpoint at the first tick 4 s of
    /// media after the last one, at most 4.5 s apart with 0.5 s ticks (ADR-0006 decision 8; review R4-05).
    @Test func checkpointIntervalIsMediaTimeAtFastRates() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 1_234)  // off the tick grid, so the next tick lands up to 0.5 s past 4 s
        h.service.setRate(3)
        h.service.play()
        h.run(10)  // 30 s of media
        let checkpoints = h.memory.history.filter { $0.reason == .periodic || $0.reason == .seek }
        #expect(checkpoints.filter { $0.reason == .periodic }.count >= 5)
        let gaps = zip(checkpoints, checkpoints.dropFirst()).map { $1.lastGlobalMs - $0.lastGlobalMs }
        #expect(gaps.allSatisfy { $0 >= 4_000 && $0 <= 4_500 }, "gaps \(gaps) ms")
        #expect(gaps.contains { $0 > 4_000 }, "the seek off the grid makes one gap longer than 4 s: \(gaps) ms")
    }

    @Test func positionWriteFailureIsReportedNotHidden() async throws {
        let h = try Harness()
        await h.load()
        h.memory.failWrites = true
        h.service.play()
        h.run(6)
        #expect(h.service.lastCheckpointError != nil)
        h.memory.failWrites = false
        h.run(6)
        #expect(h.service.lastCheckpointError == nil)
    }

    // MARK: Last versus furthest, listening totals

    @Test func lastAndFurthestAreSeparateAndAJumpAloneNeverAdvancesFurthest() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(50)
        #expect(abs(h.service.furthestGlobalMs - 50_000) <= 1_100)
        await h.service.seek(toGlobalMs: 10_000)
        h.run(5)
        h.service.pause()
        let c = try #require(h.memory.history.last)
        #expect(abs(c.lastGlobalMs - 15_000) <= 100)
        #expect(abs(c.furthestGlobalMs - 50_000) <= 1_100)
        // Jumping ahead (seek-to-end, T28) and listening there does not move the frontier.
        await h.service.seek(toGlobalMs: 170_000)
        h.service.play()
        h.run(5)
        #expect(abs(h.service.furthestGlobalMs - 50_000) <= 1_100)
        // Listening time counts wall time while main playback runs: 50 + 5 + 5 s.
        #expect(abs(h.service.listenedMs - 60_000) <= 200)
    }

    /// Review R1-02: after any forward jump the frontier must follow sustained listening again, or a single 15 s skip
    /// would pin furthest progress for the rest of the book.
    @Test func furthestFollowsSustainedListeningAfterASkip() async throws {
        let h = try Harness(durations: [3_600, 3_600, 3_600])
        await h.load()
        h.service.play()
        h.run(600)  // 10 minutes
        #expect(abs(h.service.furthestGlobalMs - 600_000) <= 1_100)
        await h.service.skip(bySeconds: 15)
        let jumpedTo = h.service.currentGlobalMs
        #expect(abs(jumpedTo - 615_000) <= 100)
        // Less than the adoption threshold after the jump: the frontier stays where contiguous listening left it.
        h.run(Double(PlaybackService.frontierAdoptionMs) / 1000 - 1.5)
        #expect(abs(h.service.furthestGlobalMs - 600_000) <= 1_100)
        // Past the threshold, the run that started at the jump becomes the frontier and keeps it moving.
        h.run(3)
        #expect(abs(h.service.furthestGlobalMs - h.service.currentGlobalMs) <= 1_100)
        h.run(7_200 - 31.5)  // two hours after the skip in total, across a member boundary
        h.service.pause()
        let last = h.service.currentGlobalMs
        #expect(abs(last - (615_000 + 7_200_000)) <= 1_000)
        #expect(abs(h.service.furthestGlobalMs - last) <= 1_100, "furthest \(h.service.furthestGlobalMs) ms, last \(last) ms")
        let c = try #require(h.memory.history.last)
        #expect(c.furthestGlobalMs == h.service.furthestGlobalMs)
        #expect(c.furthest.assetID == h.edition.ids[2])
        // Listening time is wall time of main playback: 10 min + 2 h.
        #expect(abs(h.service.listenedMs - 7_800_000) <= 200)
    }

    @Test func furthestFollowsListeningAfterAChapterJumpAtFastRates() async throws {
        let h = try Harness(durations: [600, 600, 600])
        let chapters: [UUID: [ChapterInfo]] = [h.edition.ids[1]: [ChapterInfo(title: "B1", startMs: 0, endMs: 300_000),
                                                                   ChapterInfo(title: "B2", startMs: 300_000, endMs: 600_000)]]
        await h.load(chapters: chapters)
        h.service.setRate(3)
        h.service.play()
        h.run(20)  // 60 s of media
        await h.service.nextChapter()
        await h.service.nextChapter()  // B2 at 900 s
        #expect(h.service.currentGlobalMs == 900_000)
        h.run(9)  // 27 s of media: below the threshold, which counts media time
        #expect(abs(h.service.furthestGlobalMs - 60_000) <= 3_100)
        h.run(2)  // 33 s of media
        #expect(abs(h.service.furthestGlobalMs - h.service.currentGlobalMs) <= 3_100)
        #expect(h.service.furthestGlobalMs > 930_000)
    }

    @Test func seekingNearTheEndAndListeningThereDoesNotMoveFurthest() async throws {
        let h = try Harness()
        await h.load()
        h.service.play()
        h.run(20)
        await h.service.seek(toGlobalMs: 165_000)  // 15 s before the end of the 180 s edition (T28)
        h.run(20)  // plays to the end
        #expect(h.service.currentGlobalMs == 180_000)
        #expect(abs(h.service.furthestGlobalMs - 20_000) <= 1_100)
        // Going back behind the frontier and listening past it moves it, as contiguous listening always does.
        await h.service.seek(toGlobalMs: 15_000)
        h.service.play()
        h.run(12)
        #expect(abs(h.service.furthestGlobalMs - 27_000) <= 1_100)
    }

    @Test func listeningTotalsCountWallTimeNotMediaTime() async throws {
        let h = try Harness()
        await h.load()
        h.service.setRate(2)
        h.service.play()
        h.run(20)
        h.service.pause()
        #expect(abs(h.service.listenedMs - 20_000) <= 100)
        #expect(abs(h.service.currentGlobalMs - 40_000) <= 100)
        h.run(30)  // paused time is not listening time
        #expect(abs(h.service.listenedMs - 20_000) <= 100)
    }

    /// Review R2-02: a stall while the service says playing (the slow first seek of a cold MP3 resume, buffering)
    /// moves no media, so it is not listening time (plan 12: observed playback intervals).
    @Test func listeningTotalsExcludeStallsWithoutMediaProgress() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 10_000)
        h.service.setRate(2)
        h.engine.stallSeconds = 8  // no audio for 8 s after play()
        h.service.play()
        h.run(8)
        #expect(h.service.status == .playing)
        #expect(h.service.currentGlobalMs == 10_000)
        h.run(12)  // then 12 s of playback at 2x
        #expect(abs(h.service.currentGlobalMs - 34_000) <= 100)
        h.service.pause()
        #expect(abs(h.service.listenedMs - 12_000) <= 100, "listened \(h.service.listenedMs) ms")
        // A stall in the middle of playback (buffering) is excluded the same way.
        h.service.play()
        h.run(5)
        h.engine.stallSeconds = 3
        h.run(3)
        h.run(5)
        h.service.pause()
        #expect(abs(h.service.listenedMs - 22_000) <= 100, "listened \(h.service.listenedMs) ms")
        #expect(h.memory.history.last?.listenedMs == h.service.listenedMs)
    }

    // MARK: Rate

    @Test func rateIsClampedToHalfToThree() async throws {
        let h = try Harness()
        await h.load()
        h.service.setRate(0.1)
        #expect(h.service.rate == 0.5)
        h.service.setRate(9)
        #expect(h.service.rate == 3)
        h.service.setRate(1.5)
        #expect(h.engine.rate == 1.5)
        #expect(AVQueuePlayerEngine.pitchAlgorithm == .timeDomain)
    }

    // MARK: Multi-file timeline (T20)

    @Test func crossesMemberBoundariesInOrderWithoutSkippingOrRepeating() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 55_000)
        h.service.play()
        h.run(10)
        #expect(h.service.currentPoint?.assetID == h.edition.ids[1])
        #expect(abs(h.service.currentGlobalMs - 65_000) <= 60)
        await h.service.seek(toGlobalMs: 147_000)
        h.run(10)
        #expect(h.service.currentPoint?.assetID == h.edition.ids[2])
        h.run(40)  // to the end of the edition
        #expect(h.service.status == .paused)
        #expect(h.service.currentGlobalMs == 180_000)
        #expect(h.engine.visited == [0, 1, 2])
    }

    /// The item-change checkpoint names the member that plays next, whether the engine reports the end of an item
    /// before (AVQueuePlayer) or after advancing its queue.
    @Test("Item-change checkpoint names the new member", arguments: [true, false])
    func itemChangeCheckpointNamesTheNewMember(notifiesBeforeAdvancing: Bool) async throws {
        let h = try Harness()
        h.engine.notifiesBeforeAdvancing = notifiesBeforeAdvancing
        await h.load()
        await h.service.seek(toGlobalMs: 58_000)
        h.service.play()
        h.run(4)  // crosses into member 2 at 60 s
        let change = try #require(h.memory.history.first { $0.reason == .itemChange })
        // At the start of member 2: exactly 0 when the engine has not advanced yet, or the one 50 ms fake-clock step
        // it has already played into member 2 when it advanced first.
        #expect(change.last.assetID == h.edition.ids[1])
        #expect((0...50).contains(change.last.ms))
        #expect(change.lastGlobalMs == 60_000 + change.last.ms)
        #expect(h.engine.visited == [0, 1])
        #expect(h.service.currentPoint?.assetID == h.edition.ids[1])
        #expect(abs(h.service.currentGlobalMs - 62_000) <= 60)
    }

    @Test func missingMemberBlocksOnlyItsSegment() async throws {
        let h = try Harness(missing: [1])
        await h.load()
        await h.service.seek(toGlobalMs: 55_000)
        h.service.play()
        h.run(10)
        #expect(h.service.status == .segmentUnavailable(memberIndex: 1))
        #expect(h.service.currentGlobalMs == 60_000)
        #expect(!h.engine.isPlaying)
        #expect(h.memory.history.last?.reason == .blocked)
        h.service.play()  // cannot play the missing segment
        #expect(h.session.activations == 1)
        #expect(!h.engine.isPlaying)
        await h.service.seek(toGlobalMs: 155_000)  // member 3 is available
        #expect(h.service.status == .paused)
        h.service.play()
        h.run(5)
        #expect(h.service.status == .playing)
        #expect(h.service.currentPoint?.assetID == h.edition.ids[2])
        await h.service.seek(toGlobalMs: 100_000)  // back into the missing member
        #expect(h.service.status == .segmentUnavailable(memberIndex: 1))
    }

    @Test func undecodableMemberFailsWithItsIndex() async throws {
        let h = try Harness()
        h.engine.failMember = 2
        await h.load()
        await h.service.seek(toGlobalMs: 160_000)
        #expect(h.service.status == .failed(memberIndex: 2, .decodeError("could not open member")))
    }

    /// Plan 10.1 error states: a member that is not on this device (unavailable source), a member whose file is
    /// gone (missing file) and a member that does not decode are reported differently, each with its index.
    @Test func errorStatesDistinguishUnavailableMissingAndUndecodable() async throws {
        let h = try Harness(missing: [0], deletedFiles: [2])
        await h.load()
        #expect(h.service.status == .segmentUnavailable(memberIndex: 0))
        await h.service.seek(toGlobalMs: 155_000)
        #expect(h.service.status == .failed(memberIndex: 2, .missingFile))
        h.service.play()
        #expect(!h.engine.isPlaying)
        #expect(h.service.status == .failed(memberIndex: 2, .missingFile))
        await h.service.seek(toGlobalMs: 70_000)  // member 2 is fine
        #expect(h.service.status == .paused)
    }

    @Test func aDeletedNextMemberStopsAtItsStartWithoutCuttingTheCurrentOne() async throws {
        let h = try Harness(deletedFiles: [1])
        await h.load()
        await h.service.seek(toGlobalMs: 50_000)
        #expect(h.engine.queuedMemberIndices == [0])  // the missing file is never queued
        h.service.play()
        h.run(9)
        #expect(h.service.status == .playing)  // member 1 plays to its end
        h.run(2)
        #expect(h.service.status == .failed(memberIndex: 1, .missingFile))
        #expect(h.service.currentGlobalMs == 60_000)
        #expect(!h.engine.isPlaying)
    }

    @Test func aQueuedMemberThatFailsToDecodeBlocksOnlyItsSegment() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 50_000)
        h.service.play()
        h.run(2)
        h.engine.failQueued(1)
        #expect(h.service.status == .playing)  // the current member is unaffected
        h.run(9)
        #expect(h.service.status == .failed(memberIndex: 1, .decodeError("simulated decode failure")))
        #expect(h.service.currentGlobalMs == 60_000)
        await h.service.seek(toGlobalMs: 155_000)  // member 3 still plays
        #expect(h.service.status == .paused)
        h.service.play()
        #expect(h.service.status == .playing)
    }

    @Test func playAtTheEndOfTheEditionDoesNotClaimPlayback() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 178_000)
        h.service.play()
        h.run(5)
        #expect(h.service.status == .paused)
        #expect(h.service.currentGlobalMs == 180_000)
        h.service.play()
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
    }

    @Test func reorderCreatesARevisionAndKeepsTheFileLocalPosition() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 70_000)  // member 2 at 10 s
        let point = try #require(h.service.currentPoint)
        let ids = h.edition.ids
        try await h.service.reorder([ids[1], ids[0], ids[2]])
        #expect(h.service.timeline?.revision == 2)
        #expect(h.service.currentPoint == point)
        #expect(h.service.currentGlobalMs == 10_000)
        #expect(h.memory.history.last?.reason == .reorder)
        #expect(h.memory.history.last?.timelineRevision == 2)
    }

    @Test func relaunchResumesFromTheDurableCheckpoint() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-pos-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let edition = try TestEdition()
        do {
            let engine = FakeEngine(durations: edition.engineDurations)
            let clock = ManualClock()
            let s = PlaybackService(engine: engine, previewPlayer: FakePreview(), session: SpySession(), positions: FilePositionStore(directory: dir), clock: clock, fileExists: { _ in true })
            await s.load(timeline: edition.timeline, resolveFile: edition.resolver)
            await s.seek(toGlobalMs: 100_000)
            s.play()
            engine.run(13, clock: clock)  // "crash" without a pause
        }
        let engine = FakeEngine(durations: edition.engineDurations)
        let s = PlaybackService(engine: engine, previewPlayer: FakePreview(), session: SpySession(), positions: FilePositionStore(directory: dir), fileExists: { _ in true })
        await s.load(timeline: edition.timeline, resolveFile: edition.resolver)
        #expect(s.currentGlobalMs >= 108_000 && s.currentGlobalMs <= 113_000, "resumed at \(s.currentGlobalMs)")
        #expect(s.listenedMs >= 8_000)
    }

    // MARK: Chapters

    @Test func chapterNavigationAcrossFiles() async throws {
        let h = try Harness()
        let chapters: [UUID: [ChapterInfo]] = [
            h.edition.ids[1]: [ChapterInfo(title: "B1", startMs: 0, endMs: 40_000), ChapterInfo(title: "B2", startMs: 40_000, endMs: 90_000)],
        ]
        await h.load(chapters: chapters)
        #expect(h.service.chapters.map(\.title) == ["part1.mp3", "B1", "B2", "part3.mp3"])
        #expect(h.service.chapters.map(\.startGlobalMs) == [0, 60_000, 100_000, 150_000])
        await h.service.nextChapter()
        #expect(h.service.currentGlobalMs == 60_000)
        await h.service.nextChapter()
        #expect(h.service.currentGlobalMs == 100_000)
        await h.service.seek(toGlobalMs: 110_000)
        await h.service.previousChapter()  // more than 3 s in: start of this chapter
        #expect(h.service.currentGlobalMs == 100_000)
        await h.service.previousChapter()  // at the start: previous chapter
        #expect(h.service.currentGlobalMs == 60_000)
    }

    // MARK: Interruptions and routes (T19), through posted notifications

    func observer(_ h: Harness, center: NotificationCenter) -> AudioSessionObserver {
        AudioSessionObserver(service: h.service, center: center, session: nil)
    }

    func postInterruption(_ center: NotificationCenter, began: Bool, shouldResume: Bool = false) {
        var info: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: (began ? AVAudioSession.InterruptionType.began : .ended).rawValue]
        if !began { info[AVAudioSessionInterruptionOptionKey] = (shouldResume ? AVAudioSession.InterruptionOptions.shouldResume : []).rawValue }
        center.post(name: AVAudioSession.interruptionNotification, object: nil, userInfo: info)
    }

    func postRoute(_ center: NotificationCenter, _ reason: AVAudioSession.RouteChangeReason) {
        center.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue])
    }

    @Test func interruptionPausesAndResumesOnlyWhenSystemSaysAndUserWasPlaying() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        h.service.play()
        h.run(3)
        postInterruption(center, began: true)
        #expect(h.service.status == .paused)
        #expect(h.memory.history.last?.reason == .interruption)
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .playing)

        // Ended without shouldResume: stays paused.
        postInterruption(center, began: true)
        postInterruption(center, began: false, shouldResume: false)
        #expect(h.service.status == .paused)

        // Was paused when the interruption began: never resumes.
        postInterruption(center, began: true)
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .paused)

        // User paused during the interruption: does not resume.
        h.service.play()
        postInterruption(center, began: true)
        h.service.pause()
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .paused)
        #expect(o.log.interruptionsBegan == 4)
        #expect(o.log.interruptionsEnded == 4)
    }

    @Test func headphoneRemovalPausesAndNothingStartsPlaybackOnARouteChange() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        h.service.play()
        h.run(2)
        postRoute(center, .oldDeviceUnavailable)
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
        #expect(h.memory.history.last?.reason == .routeChange)
        for reason: AVAudioSession.RouteChangeReason in [.newDeviceAvailable, .categoryChange, .override, .routeConfigurationChange] {
            postRoute(center, reason)
            #expect(h.service.status == .paused)
        }
        // An interruption that ends with shouldResume after a route-change pause does not resume either.
        postInterruption(center, began: true)
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .paused)
        #expect(o.log.routeChanges.first == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue)
    }

    @Test func observerReceivesTheSystemNotificationsFromTheSharedSession() async throws {
        let h = try Harness()
        await h.load()
        let o = AudioSessionObserver(service: h.service)  // default center, the shared AVAudioSession
        h.service.play()
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
                                        userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        #expect(h.service.status == .paused)
        #expect(o.log.routeChanges.count == 1)
    }

    // MARK: Preview (plan 10.3; T22)

    @Test func previewRestoresTheMainContextAndNeverTouchesProgress() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 90_000)
        h.service.play()
        h.run(30)  // listening from 90 s to 120 s
        let point = h.service.currentPoint
        let global = h.service.currentGlobalMs
        let ok = await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a"))
        #expect(ok)
        #expect(h.service.mode == .preview)
        #expect(!h.engine.isPlaying)
        // Main listening up to the preview is counted when main pauses; nothing after that.
        let atStart = (h.service.furthestGlobalMs, h.service.listenedMs)
        #expect(abs(atStart.1 - 30_000) <= 100)
        let writesBefore = h.memory.history.count
        h.run(25)  // the excerpt plays; main is paused
        #expect(h.service.listenedMs == atStart.1)
        #expect(h.service.furthestGlobalMs == atStart.0)
        h.preview.finish()
        #expect(h.service.mode == .main)
        #expect(h.service.currentPoint == point)
        #expect(h.service.currentGlobalMs == global)
        #expect(h.service.status == .playing)  // it was playing before preview
        #expect(h.service.furthestGlobalMs == atStart.0)
        #expect(h.service.listenedMs == atStart.1)
        // Nothing was written during the preview, and the preview-start checkpoint holds the main position.
        #expect(h.memory.history.count == writesBefore)
        #expect(h.memory.history.last?.reason == .previewStart)
        #expect(h.memory.history.last?.lastGlobalMs == global)
    }

    @Test func interruptionDuringPreviewRestoresMainContextPaused() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        await h.service.seek(toGlobalMs: 125_000)
        h.service.play()
        h.run(5)
        let before = (h.service.currentGlobalMs, h.service.furthestGlobalMs, h.service.listenedMs)
        _ = await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a"))
        h.run(3)
        postInterruption(center, began: true)
        #expect(h.service.mode == .main)
        #expect(!h.preview.isPlaying)
        #expect(h.service.currentGlobalMs == before.0)
        #expect(h.service.status == .paused)
        h.run(60)  // a phone call
        postInterruption(center, began: false, shouldResume: true)
        #expect(h.service.status == .paused)  // the user was previewing, not listening
        #expect(h.service.currentGlobalMs == before.0)
        #expect(h.service.furthestGlobalMs == before.1)
        #expect(h.service.listenedMs == before.2)
        #expect(o.log.interruptionsBegan == 1)
    }

    @Test func lifecycleDuringPreviewPersistsTheMainPosition() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 42_000)
        _ = await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a"), startSeconds: 0, endSeconds: 30)
        h.service.handleLifecycle(.didEnterBackground)
        #expect(h.memory.history.last?.reason == .lifecycle)
        #expect(h.memory.history.last?.lastGlobalMs == 42_000)
        // Transport commands during preview do not move the main session.
        h.service.play()
        await h.service.seek(toGlobalMs: 5_000)
        #expect(h.service.mode == .preview)
        h.service.endPreview(restoringPlayback: true)
        #expect(h.service.currentGlobalMs == 42_000)
        #expect(h.service.status == .paused)  // it was paused before preview
        #expect(h.preview.played.first?.last?.endSeconds == 30)
    }

    @Test func routeLossDuringPreviewStopsPreviewAndKeepsMainPaused() async throws {
        let center = NotificationCenter()
        let h = try Harness()
        await h.load()
        let o = observer(h, center: center)
        h.service.play()
        h.run(4)
        let at = h.service.currentGlobalMs
        _ = await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a"))
        postRoute(center, .oldDeviceUnavailable)
        #expect(h.service.mode == .main)
        #expect(!h.preview.isPlaying)
        #expect(h.service.status == .paused)
        #expect(h.service.currentGlobalMs == at)
        #expect(o.log.routeChanges.count == 1)
    }

    /// Review R5-02: loading another edition during a capture preview stops the preview (before the fix it kept
    /// playing over the new edition, with the audio session released under it), writes the outgoing edition's last
    /// checkpoint at its saved main point with its progress untouched, releases the session once, and loads the new
    /// edition paused. A late end of the old preview changes nothing.
    @Test func loadingAnotherEditionDuringAPreviewStopsThePreview() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 30_000)
        h.service.play()
        h.run(2)
        #expect(await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a")))
        #expect(h.preview.isPlaying && !h.engine.isPlaying)
        let saved = try #require(h.service.savedMainContext)
        let progress = (h.service.furthestGlobalMs, h.service.listenedMs)
        h.run(3)  // the preview plays
        let other = try TestEdition(durations: [40, 50])
        await h.service.load(timeline: other.timeline, resolveFile: other.resolver)
        #expect(!h.preview.isPlaying, "the old edition's preview kept playing")
        #expect(h.preview.onFinish == nil)
        #expect(h.service.mode == .main && h.service.savedMainContext == nil)
        #expect(h.service.timeline?.editionID == other.timeline.editionID)
        #expect(h.service.status == .paused && !h.engine.isPlaying)
        #expect(h.service.currentPoint == AudioPoint(assetID: other.ids[0], ms: 0))
        #expect(h.session.deactivations == 1 && !h.session.isActive)
        // The outgoing edition resumes where its listener left it: its saved main point, progress untouched.
        let outgoing = try #require(h.memory.history.last { $0.editionID == h.edition.timeline.editionID })
        #expect(outgoing.reason == .editionChange)
        #expect(outgoing.last == saved.point)
        #expect(outgoing.furthestGlobalMs == progress.0 && outgoing.listenedMs == progress.1)
        // The new edition starts with its own progress, not the old one's.
        #expect(h.service.furthestGlobalMs == 0 && h.service.listenedMs == 0)
        // A late end of the old preview changes nothing; playing the new edition plays only the main engine.
        h.preview.finish()
        #expect(h.service.mode == .main && h.service.status == .paused && h.session.deactivations == 1)
        h.service.play()
        #expect(h.engine.isPlaying && !h.preview.isPlaying)
    }

    /// Loading another edition while main plays (review R5-02): main stops, its listening is counted, and the outgoing
    /// edition's checkpoint records where it stopped (otherwise up to 5 s of it would be lost, the periodic rhythm).
    @Test func loadingAnotherEditionWhilePlayingCheckpointsTheOutgoingEdition() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 10_000)
        h.service.play()
        h.run(7.3)  // past the last periodic checkpoint
        let point = try #require(h.service.currentPoint)
        let other = try TestEdition(durations: [40])
        await h.service.load(timeline: other.timeline, resolveFile: other.resolver)
        let outgoing = try #require(h.memory.history.last { $0.editionID == h.edition.timeline.editionID })
        #expect(outgoing.reason == .editionChange)
        #expect(outgoing.last == point)
        #expect(abs(outgoing.lastGlobalMs - 17_300) <= 1)
        #expect(abs(outgoing.listenedMs - 7_300) <= 1)
        #expect(h.session.events == ["activate", "deactivate"])
        #expect(h.service.status == .paused && !h.engine.isPlaying)
        // Reloading the first edition resumes it from that checkpoint.
        await h.service.load(timeline: h.edition.timeline, resolveFile: h.edition.resolver)
        #expect(h.service.currentPoint == point)
        #expect(abs(h.service.listenedMs - 7_300) <= 1)
    }

    /// Review R1-06: a pending cross-file capture previews all its source ranges in order, not only the first.
    @Test func pendingCrossFilePreviewPlaysEveryRangeInOrder() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 120_000)
        let ids = h.edition.ids
        // The preceding 30 s at 75 s global: member 1 from 45 s to its end, then member 2 from 0 to 15 s.
        let ranges = try h.edition.timeline.ranges(globalStartMs: 45_000, globalEndMs: 75_000)
        #expect(ranges == [AudioRange(assetID: ids[0], startMs: 45_000, endMs: 60_000), AudioRange(assetID: ids[1], startMs: 0, endMs: 15_000)])
        let segments = try #require(h.service.previewSegments(for: ranges))
        #expect(segments == [PreviewSegment(url: URL(fileURLWithPath: "/fake/part1.mp3"), startSeconds: 45, endSeconds: 60),
                             PreviewSegment(url: URL(fileURLWithPath: "/fake/part2.mp3"), startSeconds: 0, endSeconds: 15)])
        let writes = h.memory.history.count
        #expect(await h.service.beginPreview(segments))
        #expect(h.preview.played.last == segments)
        h.preview.finish()
        #expect(h.service.mode == .main)
        #expect(h.service.currentGlobalMs == 120_000)
        #expect(h.memory.history.count == writes)
    }

    @Test func previewRejectsSegmentsItCannotPlayBackToBackAndUnavailableSources() async throws {
        let h = try Harness(missing: [1])
        await h.load()
        await h.service.seek(toGlobalMs: 10_000)
        let a = URL(fileURLWithPath: "/fake/a.m4a"), b = URL(fileURLWithPath: "/fake/b.m4a")
        // A later segment that does not start at 0 cannot be positioned before it plays: refused, nothing changes.
        #expect(await h.service.beginPreview([PreviewSegment(url: a, startSeconds: 5, endSeconds: 9),
                                              PreviewSegment(url: b, startSeconds: 2, endSeconds: 4)]) == false)
        #expect(await h.service.beginPreview([]) == false)
        #expect(await h.service.beginPreview([PreviewSegment(url: a, startSeconds: 5, endSeconds: 5)]) == false)
        #expect(h.service.mode == .main && h.preview.played.isEmpty)
        // A pending range in a member that is not on this device has no preview.
        let ranges = try h.edition.timeline.ranges(globalStartMs: 50_000, globalEndMs: 70_000)
        #expect(h.service.previewSegments(for: ranges) == nil)
    }
}
