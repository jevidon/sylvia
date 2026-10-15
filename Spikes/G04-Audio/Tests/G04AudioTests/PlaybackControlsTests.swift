import Foundation
import MediaPlayer
import Testing
@testable import G04AudioKit

/// Plan 10.1 playback controls that ADR-0006 decides (review R6-02): configurable skip intervals, the sleep timer, the
/// rewind after a long pause and the incomplete-edition warning, over the fake engine and the manual clock.
@Suite("Playback controls: skip intervals, sleep timer, resume rewind, incomplete edition (unit)", .temporaryStores)
@MainActor
struct PlaybackControlsTests {
    // MARK: Skip intervals

    @Test func skipIntervalsAreConfigurableAndKeptInRange() async throws {
        let h = try Harness()
        await h.load()
        #expect(h.service.skipBackwardSeconds == 15 && h.service.skipForwardSeconds == 15)
        await h.service.seek(toGlobalMs: 100_000)
        h.service.setSkipIntervals(backward: 10, forward: 30)
        await h.service.skipBackward()
        #expect(h.service.currentGlobalMs == 90_000)
        await h.service.skipForward()
        #expect(h.service.currentGlobalMs == 120_000)
        h.service.setSkipIntervals(backward: 1, forward: 500)
        #expect(h.service.skipBackwardSeconds == 5 && h.service.skipForwardSeconds == 120)
        h.service.setSkipIntervals(backward: .nan, forward: 29.6)
        #expect(h.service.skipBackwardSeconds == 15 && h.service.skipForwardSeconds == 30)
    }

    /// The remote skip commands (headphones, Lock Screen, Control Center) move by the listener intervals, and Now
    /// Playing advertises them as the commands preferred intervals.
    @Test func remoteSkipCommandsUseAndAdvertiseTheIntervals() async throws {
        let h = try Harness()
        await h.load()
        let np = NowPlayingController(service: h.service, publishesToSystem: false)
        await h.service.seek(toGlobalMs: 100_000)
        h.service.setSkipIntervals(backward: 10, forward: 45)
        #expect(await np.perform(.skipBackward) == .success)
        #expect(h.service.currentGlobalMs == 90_000)
        #expect(await np.perform(.skipForward) == .success)
        #expect(h.service.currentGlobalMs == 135_000)
        let snap = try #require(np.published)
        #expect(snap.skipBackwardSeconds == 10 && snap.skipForwardSeconds == 45)
    }

    // MARK: Sleep timer

    /// The countdown is wall time of main playback only: a pause does not use it up, and at 2x it still counts wall
    /// seconds. When it runs out main pauses with its own checkpoint, and the audio session is kept (an app the book
    /// interrupted is not told to resume while the listener sleeps); the next pause by the listener releases it.
    @Test func sleepTimerCountsPlaybackTimeOnlyAndKeepsTheSession() async throws {
        let h = try Harness(durations: [600, 600, 600])
        await h.load()
        h.service.play()
        h.service.setSleepTimer(.after(seconds: 60))
        h.run(30)
        h.service.pause()
        h.run(600)
        #expect(h.service.sleepRemainingSeconds.map { abs($0 - 30) < 0.01 } == true, "\(String(describing: h.service.sleepRemainingSeconds))")
        h.service.play()
        h.service.setRate(2)
        h.run(29)
        #expect(h.service.status == .playing)
        h.run(1.5)
        #expect(h.service.status == .paused)
        #expect(h.memory.history.last?.reason == .sleepTimer)
        #expect(h.service.sleepTimer == nil && h.service.sleepRemainingSeconds == nil)
        // 30 s at 1x, then 30 s at 2x: 90 s of the book.
        #expect(abs(h.service.currentGlobalMs - 90_000) <= 600, "\(h.service.currentGlobalMs)")
        #expect(h.session.events == ["activate", "deactivate", "activate"])
        #expect(h.session.isActive)
        h.service.pause()
        #expect(h.session.events == ["activate", "deactivate", "activate", "deactivate"])
    }

    @Test func sleepTimerAtTheEndOfAChapterStopsAtItsEnd() async throws {
        let h = try Harness(durations: [600, 600, 600])
        let chapters: [UUID: [ChapterInfo]] = [h.edition.ids[1]: [ChapterInfo(title: "B1", startMs: 0, endMs: 250_000),
                                                                   ChapterInfo(title: "B2", startMs: 250_000, endMs: 600_000)]]
        await h.load(chapters: chapters)
        await h.service.seek(toGlobalMs: 840_000)  // in B1, 10 s before its end at 850 s
        h.service.setSleepTimer(.endOfChapter)
        #expect(h.service.sleepStopGlobalMs == 850_000)
        h.service.play()
        h.run(9.6)
        #expect(h.service.status == .playing)
        h.run(1)
        #expect(h.service.status == .paused)
        #expect(h.memory.history.last?.reason == .sleepTimer)
        // The first tick at or after the end: at most one tick (0.5 s of media) past it.
        #expect(h.service.currentGlobalMs >= 850_000 && h.service.currentGlobalMs <= 850_500, "\(h.service.currentGlobalMs)")
        #expect(h.service.sleepTimer == nil)
    }

    /// The stop follows the listener: after a skip into a later chapter the timer stops at the end of that chapter, not at
    /// once at the first tick past the old stop; a resume rewind keeps the stop it had.
    @Test func endOfChapterSleepTimerFollowsASeek() async throws {
        let h = try Harness(durations: [600, 600, 600])
        let chapters: [UUID: [ChapterInfo]] = [h.edition.ids[1]: [ChapterInfo(title: "B1", startMs: 0, endMs: 250_000),
                                                                   ChapterInfo(title: "B2", startMs: 250_000, endMs: 600_000)]]
        await h.load(chapters: chapters)
        await h.service.seek(toGlobalMs: 700_000)  // in B1 (600 to 850 s)
        h.service.setSleepTimer(.endOfChapter)
        #expect(h.service.sleepStopGlobalMs == 850_000)
        h.service.play()
        h.run(2)
        await h.service.seek(toGlobalMs: 900_000)  // into B2 (850 to 1,200 s)
        #expect(h.service.sleepStopGlobalMs == 1_200_000)
        h.run(5)
        #expect(h.service.status == .playing, "the timer stopped at once after the skip")
        await h.service.seek(toGlobalMs: 1_195_000)
        h.run(6)
        #expect(h.service.status == .paused && h.memory.history.last?.reason == .sleepTimer)
        #expect(h.service.currentGlobalMs >= 1_200_000 && h.service.currentGlobalMs <= 1_200_500)
    }

    /// Without chapters a member file is the chapter: the timer stops at the end of the member, and the checkpoint names
    /// the start of the next member (AVQueuePlayer reports the end before it advances; ADR-0006 decision 10).
    @Test func sleepTimerAtTheEndOfAMemberStopsAtTheStartOfTheNext() async throws {
        let h = try Harness()  // 60 s, 90 s and 30 s, no chapters
        await h.load()
        await h.service.seek(toGlobalMs: 50_000)
        h.service.setSleepTimer(.endOfChapter)
        #expect(h.service.sleepStopGlobalMs == 60_000)
        h.service.play()
        h.run(12)
        #expect(h.service.status == .paused)
        #expect(!h.engine.isPlaying)
        let c = try #require(h.memory.history.last)
        #expect(c.reason == .sleepTimer)
        #expect(c.last == AudioPoint(assetID: h.edition.ids[1], ms: 0))
        #expect(h.service.currentGlobalMs == 60_000)
    }

    // MARK: Rewind after a long pause

    /// Plan 10.1: resuming after a long pause may rewind a configurable small amount, but never changes a saved
    /// bookmark or quote. A short pause resumes in place; a long one resumes earlier, through a seek with its own
    /// checkpoint; the furthest position is never lowered; stored captures are untouched.
    @Test func resumingAfterALongPauseRewindsAndChangesNoProgressOrCapture() async throws {
        let h = try Harness(durations: [600, 600, 600])
        await h.load()
        let captures = CaptureService(store: try temporaryStore(), exporter: ScriptedExporter(), resolveSource: h.edition.resolver)
        h.service.setResumeRewind(.init(afterPauseSeconds: 300, rewindSeconds: 10))
        h.service.play()
        h.run(120)
        let bookmark = try captures.bookmark(timeline: h.edition.timeline, atGlobalMs: h.service.currentGlobalMs, note: "kept", idempotencyKey: "b")
        let moment = try captures.captureAudio(timeline: h.edition.timeline, atGlobalMs: h.service.currentGlobalMs, note: "kept too", idempotencyKey: "m")
        h.service.pause()
        let stored = [try await captures.record(bookmark.id), try await captures.record(moment.id)]
        // A short pause: resumes where it stopped.
        h.run(299)
        h.service.play()
        #expect(h.service.status == .playing && h.service.currentGlobalMs == 120_000)
        h.run(10)
        h.service.pause()
        #expect(abs(h.service.furthestGlobalMs - 130_000) <= 1_100)
        // A long pause: resumes 10 s earlier.
        h.run(301)
        h.service.play()
        #expect(h.service.isPlayingOrStarting)
        await h.service.resumeRewindTask?.value
        #expect(h.service.status == .playing)
        #expect(h.service.currentGlobalMs == 120_000)
        #expect(h.memory.history.last?.reason == .resumeRewind)
        #expect(h.memory.history.last?.lastGlobalMs == 120_000)
        h.run(5)
        #expect(abs(h.service.furthestGlobalMs - 130_000) <= 1_100, "the rewind lowered or moved the furthest position")
        #expect([try await captures.record(bookmark.id), try await captures.record(moment.id)] == stored)
        // Replayed seconds are listening: 120 + 10 + 5 s.
        #expect(abs(h.service.listenedMs - 135_000) <= 200)
    }

    /// After a relaunch the pause is measured from the wall-clock time of the stored checkpoint.
    @Test func aRelaunchLongAfterThePauseRewindsOnTheFirstPlay() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-rewind-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let edition = try TestEdition(durations: [600, 600])
        let clock = ManualClock()
        func service(_ engine: FakeEngine) -> PlaybackService {
            PlaybackService(engine: engine, previewPlayer: FakePreview(), session: SpySession(), positions: FilePositionStore(directory: dir),
                            clock: clock, fileExists: { _ in true })
        }
        do {
            let engine = FakeEngine(durations: edition.engineDurations)
            let s = service(engine)
            await s.load(timeline: edition.timeline, resolveFile: edition.resolver)
            s.play()
            engine.run(200, clock: clock)
            s.pause()
        }
        // Relaunched four minutes later: resumes in place.
        clock.advance(240)
        let soon = FakeEngine(durations: edition.engineDurations)
        let s1 = service(soon)
        s1.setResumeRewind(.init(afterPauseSeconds: 300, rewindSeconds: 15))
        await s1.load(timeline: edition.timeline, resolveFile: edition.resolver)
        s1.play()
        #expect(s1.status == .playing && s1.currentGlobalMs == 200_000)
        s1.pause()
        // Relaunched an hour after that pause: the first play rewinds 15 s.
        clock.advance(3_600)
        let later = FakeEngine(durations: edition.engineDurations)
        let s2 = service(later)
        s2.setResumeRewind(.init(afterPauseSeconds: 300, rewindSeconds: 15))
        await s2.load(timeline: edition.timeline, resolveFile: edition.resolver)
        #expect(s2.currentGlobalMs == 200_000)
        s2.play()
        await s2.resumeRewindTask?.value
        #expect(s2.status == .playing && s2.currentGlobalMs == 185_000)
    }

    /// No rewind when the listener has positioned the playhead since the pause, after a capture preview (plan 10.3: the
    /// main context comes back exactly), or at a blocked segment; a pause during the rewind seek cancels the play; the
    /// system resume after a long interruption (a phone call) rewinds like any other resume.
    @Test func resumeRewindExceptionsAndCancellation() async throws {
        let rewind = PlaybackService.ResumeRewind(afterPauseSeconds: 300, rewindSeconds: 10)
        // A seek during the pause.
        let a = try Harness(durations: [600, 600])
        await a.load()
        a.service.setResumeRewind(rewind)
        a.service.play()
        a.run(60)
        a.service.pause()
        a.run(400)
        await a.service.seek(toGlobalMs: 500_000)
        a.service.play()
        #expect(a.service.status == .playing && a.service.currentGlobalMs == 500_000)
        // The end of a capture preview restores main exactly, however long main had been paused.
        let b = try Harness(durations: [600, 600])
        await b.load()
        b.service.setResumeRewind(rewind)
        b.service.play()
        b.run(60)
        #expect(await b.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a")))
        b.run(400)
        b.preview.finish()
        #expect(b.service.status == .playing && b.service.currentGlobalMs == 60_000)
        // A pause while the rewind seek runs cancels the play.
        b.run(10)
        b.service.pause()
        b.run(400)
        b.service.play()
        b.service.pause()
        await b.service.resumeRewindTask?.value
        #expect(b.service.status == .paused && !b.engine.isPlaying)
        #expect(b.service.currentGlobalMs == 70_000, "a cancelled resume moved the playhead")
        // The pause still counts from when it began: the next play rewinds.
        b.service.play()
        await b.service.resumeRewindTask?.value
        #expect(b.service.status == .playing && b.service.currentGlobalMs == 60_000)
        // A blocked segment: play does nothing, and no rewind moves playback into the member before it.
        let c = try Harness(missing: [1])
        await c.load()
        c.service.setResumeRewind(rewind)
        await c.service.seek(toGlobalMs: 50_000)
        c.service.play()
        c.run(15)
        #expect(c.service.status == .segmentUnavailable(memberIndex: 1))
        c.run(400)
        c.service.play()
        await c.service.resumeRewindTask?.value
        #expect(c.service.status == .segmentUnavailable(memberIndex: 1) && c.service.currentGlobalMs == 60_000)
        #expect(!c.engine.isPlaying)
        // A long interruption (a phone call) that ends with shouldResume: the system resume rewinds too.
        let d = try Harness(durations: [600, 600])
        await d.load()
        d.service.setResumeRewind(rewind)
        d.service.play()
        d.run(100)
        d.service.interruptionBegan()
        d.run(400)
        d.service.interruptionEnded(shouldResume: true)
        await d.service.resumeRewindTask?.value
        #expect(d.service.status == .playing && d.service.currentGlobalMs == 90_000)
    }

    // MARK: Incomplete edition

    /// Plan 10.1: a missing member blocks only its segment and shows an incomplete-edition warning. The warning knows
    /// every member that cannot play here before anything plays, follows the members through a reorder, and takes in
    /// a member that later fails to decode.
    @Test func incompleteEditionWarningListsTheMembersThatCannotPlay() async throws {
        let complete = try Harness()
        await complete.load()
        #expect(!complete.service.isEditionIncomplete && complete.service.unavailableMemberIndices.isEmpty)
        let h = try Harness(missing: [1], deletedFiles: [2])
        await h.load()
        #expect(h.service.isEditionIncomplete)
        #expect(h.service.unavailableMemberIndices == [1, 2])
        #expect(h.service.unavailableMembers[h.edition.ids[1]] == .notOnThisDevice)
        #expect(h.service.unavailableMembers[h.edition.ids[2]] == .missingFile)
        h.service.play()
        h.run(5)
        #expect(h.service.status == .playing, "the available member plays")
        let ids = h.edition.ids
        try await h.service.reorder([ids[2], ids[0], ids[1]])
        #expect(h.service.unavailableMemberIndices == [0, 2])
        let d = try Harness()
        await d.load()
        d.service.play()
        d.run(1)
        d.engine.failQueued(1)
        #expect(d.service.unavailableMembers[d.edition.ids[1]] == .decodeError)
        #expect(d.service.unavailableMemberIndices == [1])
    }
}
