import Foundation
import MediaPlayer
import Testing
@testable import G04AudioKit

/// Remote commands (headphones, Lock Screen, Control Center) and what Now Playing shows, over a fake engine and a fake
/// preview player (plan 10.1, 10.3; review R4-03). The controller never publishes to the shared system centers here
/// (`publishesToSystem: false`): these suites run in parallel with the real-engine suites, which own the system's
/// Now Playing state; the real-engine Now Playing test covers publishing.
@Suite("Remote commands and Now Playing (unit, fake engine and preview)")
@MainActor
struct RemoteCommandTests {
    struct Logged: Equatable {
        var name: String
        var mode: PlaybackService.Mode
        var status: MPRemoteCommandHandlerStatus
    }

    final class Recorder {
        var entries: [Logged] = []
    }

    func controller(_ h: Harness) -> (NowPlayingController, Recorder) {
        let np = NowPlayingController(service: h.service, publishesToSystem: false)
        np.titleProvider = { "Fixture book" }
        let recorder = Recorder()
        np.onCommand = { command, mode, status in recorder.entries.append(Logged(name: command.name, mode: mode, status: status)) }
        return (np, recorder)
    }

    /// During a preview of a capture while the book was playing: commands that would move the book or change its rate
    /// are refused (and shown disabled), play is accepted, and pause stops the preview and leaves the book paused at
    /// the saved place with its progress untouched and the audio session released.
    @Test func duringAPreviewNavigationIsRefusedAndPauseStopsThePreview() async throws {
        let h = try Harness()
        await h.load()
        let (np, log) = controller(h)
        await h.service.seek(toGlobalMs: 30_000)
        h.service.play()
        h.run(10)
        #expect(await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a")))
        h.preview.fakeProgress = (elapsedSeconds: 3.5, durationSeconds: 30)
        let saved = try #require(h.service.savedMainContext)
        let progress = (h.service.furthestGlobalMs, h.service.listenedMs, h.memory.history.count, h.service.rate)

        np.update()
        let previewing = try #require(np.published)
        #expect(previewing.isPreview && previewing.isPlaying)
        #expect(previewing.durationSeconds == 30 && previewing.elapsedSeconds == 3.5 && previewing.rate == 1)
        #expect(previewing.title == "Fixture book")
        #expect(previewing.enabledCommands == Set(NowPlayingController.transportCommands))
        #expect(previewing.chapterCount == nil)

        for command: NowPlayingController.Command in [.skipForward, .skipBackward, .changeRate(2), .changePosition(seconds: 100),
                                                      .nextChapter, .previousChapter] {
            #expect(await np.perform(command) == .commandFailed, "\(command.name) during a preview")
            #expect(h.service.mode == .preview && h.preview.isPlaying, "\(command.name) ended the preview")
        }
        #expect(await np.perform(.play) == .success)
        #expect(h.service.mode == .preview && h.preview.isPlaying)
        // Nothing moved: the saved point, progress, checkpoints and rate are as at the preview's start.
        #expect(h.service.savedMainContext == saved)
        #expect((h.service.furthestGlobalMs, h.service.listenedMs, h.memory.history.count, h.service.rate) == progress)

        let sessionBefore = h.session.events
        #expect(await np.perform(.togglePlayPause) == .success)
        #expect(h.service.mode == .main)
        #expect(!h.preview.isPlaying)
        #expect(h.service.status == .paused, "the book was playing before the preview, but the listener asked for silence")
        #expect(!h.engine.isPlaying)
        #expect(h.service.currentPoint == saved.point)
        #expect((h.service.furthestGlobalMs, h.service.listenedMs, h.memory.history.count) == (progress.0, progress.1, progress.2))
        #expect(h.session.events == sessionBefore + ["deactivate"], "a user stop releases the session like a user pause")

        let after = try #require(np.published)
        #expect(!after.isPreview && !after.isPlaying)
        #expect(after.elapsedSeconds == Double(h.service.currentGlobalMs) / 1000)
        #expect(after.enabledCommands == Set(NowPlayingController.transportCommands + NowPlayingController.navigationCommands))
        #expect(log.entries.filter { $0.mode == .preview }.map(\.name) ==
                ["skipForward", "skipBackward", "changePlaybackRate", "changePlaybackPosition", "nextTrack", "previousTrack", "play", "togglePlayPause"])
        #expect(log.entries.last == Logged(name: "togglePlayPause", mode: .preview, status: .success))
        // Back in the book, play resumes it from the saved place.
        #expect(await np.perform(.play) == .success)
        #expect(h.service.status == .playing)
    }

    @Test func pauseDuringAPreviewOfAPausedBookStopsItAndKeepsTheBookPaused() async throws {
        let h = try Harness()
        await h.load()
        let (np, _) = controller(h)
        await h.service.seek(toGlobalMs: 95_000)
        let point = try #require(h.service.currentPoint)
        #expect(await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a"), startSeconds: 2, endSeconds: 9))
        #expect(h.session.events == ["activate"])
        #expect(await np.perform(.pause) == .success)
        #expect(h.service.mode == .main && h.service.status == .paused)
        #expect(h.service.currentPoint == point)
        #expect(h.session.events == ["activate", "deactivate"])
        // A second pause (the book is paused): accepted, nothing changes, the session is not released twice.
        #expect(await np.perform(.pause) == .success)
        #expect(h.session.events == ["activate", "deactivate"])
    }

    /// The headphone button during a preview sends play/pause; the harness's own Play/Pause button calls the same
    /// service method.
    @Test func playPauseDuringAPreviewStopsItThroughTheService() async throws {
        let h = try Harness()
        await h.load()
        await h.service.seek(toGlobalMs: 12_000)
        h.service.play()
        h.run(2)
        #expect(await h.service.beginPreview(url: URL(fileURLWithPath: "/fake/excerpt.m4a")))
        h.service.togglePlayPause()
        #expect(h.service.mode == .main && h.service.status == .paused && !h.preview.isPlaying)
        h.service.togglePlayPause()
        #expect(h.service.status == .playing)
    }

    @Test func commandsTheServiceCannotActOnAreReportedFailed() async throws {
        // Nothing loaded.
        let empty = try Harness()
        let (idle, _) = controller(empty)
        #expect(await idle.perform(.play) == .noActionableNowPlayingItem)
        #expect(await idle.perform(.skipForward) == .noActionableNowPlayingItem)
        idle.update()
        #expect(idle.published == nil)

        // Play at a segment that is not on this device: nothing starts, so the command failed.
        let h = try Harness(missing: [1])
        await h.load()
        let (np, _) = controller(h)
        await h.service.seek(toGlobalMs: 70_000)
        #expect(h.service.status == .segmentUnavailable(memberIndex: 1))
        #expect(await np.perform(.play) == .commandFailed)
        #expect(await np.perform(.togglePlayPause) == .commandFailed)
        #expect(!h.engine.isPlaying)

        // Next chapter in the last chapter: nothing to go to.
        let c = try Harness()
        await c.load()
        let (cn, _) = controller(c)
        await c.service.seek(toGlobalMs: 175_000)
        #expect(await cn.perform(.nextChapter) == .commandFailed)
        #expect(c.service.currentGlobalMs == 175_000)
        #expect(await cn.perform(.previousChapter) == .success)
        #expect(c.service.currentGlobalMs == 150_000)
    }

    @Test func mainPlaybackCommandsAreActedOnAndReported() async throws {
        let h = try Harness()
        await h.load()
        let (np, log) = controller(h)
        #expect(await np.perform(.play) == .success)
        #expect(h.service.status == .playing)
        h.run(3)
        #expect(await np.perform(.skipForward) == .success)
        #expect(abs(h.service.currentGlobalMs - 18_000) <= 60)
        #expect(await np.perform(.changeRate(2)) == .success)
        #expect(h.service.rate == 2)
        #expect(await np.perform(.changePosition(seconds: 100)) == .success)
        #expect(h.service.currentGlobalMs == 100_000)
        let playing = try #require(np.published)
        #expect(!playing.isPreview && playing.isPlaying && playing.rate == 2 && playing.elapsedSeconds == 100)
        #expect(await np.perform(.togglePlayPause) == .success)
        #expect(h.service.status == .paused)
        #expect(log.entries.allSatisfy { $0.mode == .main && $0.status == .success })
        #expect(np.performed.count == 5)
    }
}
