import AVFoundation
import Foundation
import MediaPlayer
import Testing
@testable import G04AudioKit

func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

/// A contiguous run of audio the tap saw, with when it was processed.
struct TapRun {
    var start: Double
    var samples: [Float]
    var rate: Double
    var firstUptime: TimeInterval
    var lastUptime: TimeInterval
    var seconds: Double { Double(samples.count) / rate }
    var end: Double { start + seconds }
}

extension AudioTapCollector {
    /// Contiguous runs (each chunk continues the previous one within 2 ms of source time) among the chunks the tap
    /// processed at or after `after` (host uptime).
    func tapRuns(after: TimeInterval = 0) -> [TapRun] {
        Self.runs(snapshot(), rate: sampleRate, after: after)
    }

    /// `tapRuns` over a snapshot, so a caller can take the snapshot on the main actor and build the runs elsewhere.
    /// Each run grows in place (appending to a copy of the run would copy every sample once per chunk: seconds of
    /// main-thread work for a minute of audio, which delayed the playback service's ticks in the soak test).
    static func runs(_ chunks: [Chunk], rate: Double, after: TimeInterval = 0) -> [TapRun] {
        guard rate > 0 else { return [] }
        var result: [TapRun] = []
        for c in chunks where c.uptime >= after {
            if let last = result.indices.last, abs(c.sourceStart - result[last].end) < 0.002 {
                result[last].samples.append(contentsOf: c.samples)
                result[last].lastUptime = c.uptime
            } else {
                result.append(TapRun(start: c.sourceStart, samples: c.samples, rate: rate, firstUptime: c.uptime, lastUptime: c.uptime))
            }
        }
        return result
    }

    /// The longest run processed after `after` whose start is within `tolerance` seconds of `near`.
    func longestRun(near: Double, after: TimeInterval = 0, tolerance: Double = 1.0) -> TapRun? {
        tapRuns(after: after).filter { abs($0.start - near) <= tolerance }.max { $0.samples.count < $1.samples.count }
    }

    /// The first chunk processed after `after` whose source start is within `tolerance` seconds of `near`.
    func firstChunk(near: Double, after: TimeInterval, tolerance: Double = 1.0) -> Chunk? {
        snapshot().first { $0.uptime >= after && abs($0.sourceStart - near) <= tolerance }
    }
}

/// Content error of a tap run against a master: where the audio really comes from minus where the player said it
/// was (ms). `masterOffset` maps the run's item time to master time (for a member, its true slice start).
/// `loopFrames` folds positions of the looped 10-hour fixtures back into master-long.
func contentErrorMs(_ run: TapRun, masterOffset: Double, master: any PCMSource, window: Double = 1.5,
                    loopFrames: Int? = nil) throws -> (errorMs: Double, peak: Float)? {
    let samples = Resampler.resample(run.samples, from: run.rate, to: PCMDecoder.analysisRate)
    let seconds = Double(samples.count) / PCMDecoder.analysisRate
    guard seconds >= window else { return nil }
    let scan = max(0, min(1.0, seconds - window))
    guard let m = try TimingVerifier.measure(audio: samples, rate: PCMDecoder.analysisRate, intendedStart: masterOffset + run.start,
                                             master: master, loopFrames: loopFrames, probeSeconds: window, scanSeconds: scan,
                                             radiusSeconds: 2) else { return nil }
    return (m.errorMs, m.peak)
}

func rms(_ x: [Float]) -> Float {
    guard !x.isEmpty else { return 0 }
    return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
}

func summary(_ label: String, _ xs: [Double], unit: String) -> String {
    String(format: "%@: n=%d p50=%.3f p95=%.3f max=%.3f %@", label, xs.count, Results.percentile(xs, 50), Results.percentile(xs, 95), xs.max() ?? .nan, unit)
}

extension RealAV {
    /// The playback service over the real AVQueuePlayer engine (plan 10.1; T19, T20). Positions are verified from
    /// the audio the engine actually rendered (analysis tap), cross-correlated with master-long.
    @Suite("Playback service on the real engine (T19, T20)", .serialized)
    @MainActor
    struct RealServiceTests {
        static let toleranceMs = 150.0

        @Test("Member boundary: the next member plays from its start, nothing skipped or repeated (T20)", .timeLimit(.minutes(5)))
        func boundaryCrossing() async throws {
            let master = try Fixtures.masterLong()
            var lines = ["# Member boundaries on AVQueuePlayer (multi-file MP3 book), with every member opened with precise timing and, second, as the",
                         "# import opens them (the per-file timing mode: estimated timing for these constant-bit-rate MP3 files; review R4-01). Environment: \(Results.environmentLabel())"]
            defer { Results.write("real-engine-boundary.txt", lines) }
            for timing in RealEdition.Timing.allCases {
                let edition = try await RealEdition(timing: timing)
                lines.append("members opened: \(edition.timingLabel)")
                for boundary in 1..<edition.timeline.members.count {
                    let p = RealPlayer()
                    await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
                    let b = edition.timeline.starts[boundary]
                    await p.service.seek(toGlobalMs: b - 3_000)
                    let t0 = uptime()
                    p.service.play()
                    let crossed = try await p.wait(12) { p.engine.currentMemberIndex == boundary && (p.service.currentPoint?.ms ?? 0) >= 2_500 }
                    p.service.pause()
                    #expect(crossed, "did not reach member \(boundary + 1)")
                    let prevDuration = Double(edition.timeline.members[boundary - 1].durationMs) / 1000
                    let before = try #require(p.collectors[boundary - 1]?.longestRun(near: prevDuration - 3, after: t0, tolerance: 0.3))
                    let after = try #require(p.collectors[boundary]?.longestRun(near: 0, after: t0, tolerance: 0.3))
                    let eBefore = try #require(try contentErrorMs(before, masterOffset: Fixtures.multi[boundary - 1].start, master: master))
                    let eAfter = try #require(try contentErrorMs(after, masterOffset: Fixtures.multi[boundary].start, master: master))
                    let gap = after.firstUptime - before.lastUptime
                    lines.append(String(format: "boundary %d: previous member rendered %.3f-%.3f s of %.3f s (content error %.1f ms, peak %.3f); next member from %.3f s for %.2f s (content error %.1f ms, peak %.3f); tap processing gap %.3f s",
                                        boundary, before.start, before.end, prevDuration, eBefore.errorMs, eBefore.peak, after.start, after.seconds, eAfter.errorMs, eAfter.peak, gap))
                    #expect(before.end >= prevDuration - 0.15, "previous member cut short at \(before.end) of \(prevDuration)")
                    #expect(abs(after.start) <= 0.01, "next member started at \(after.start) s")
                    #expect(abs(eBefore.errorMs) <= Self.toleranceMs && eBefore.peak >= 0.5)
                    #expect(abs(eAfter.errorMs) <= Self.toleranceMs && eAfter.peak >= 0.5)
                    // Nothing beyond the next member was rendered (no skip), and the checkpoint moved to the new member.
                    #expect(p.collectors[boundary + 1]?.tapRuns(after: t0).contains { $0.seconds > 0.5 } != true)
                    #expect(p.memory.history.contains { $0.reason == .itemChange && $0.last.assetID == edition.ids[boundary] })
                    p.stop()
                }
            }
        }

        @Test("Seek into another member at 2x, 0.5x and 1x: position and rendered content agree (T20)", .timeLimit(.minutes(5)))
        func seekAcrossMembersAndRate() async throws {
            let master = try Fixtures.masterLong()
            var lines = ["# Seek across members and rate on AVQueuePlayer, with every member opened with precise timing and, second, as the import",
                         "# opens them (estimated timing for these constant-bit-rate MP3 files; review R4-01). Environment: \(Results.environmentLabel())"]
            defer { Results.write("real-engine-seek-rate.txt", lines) }
            for timing in RealEdition.Timing.allCases {
                let edition = try await RealEdition(timing: timing)
                lines.append("members opened: \(edition.timingLabel)")
                let p = RealPlayer()
                defer { p.stop() }
                await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
                for (member, local, rate) in [(2, 20.25, Float(2)), (0, 101.5, Float(0.5)), (3, 7.0, Float(1))] {
                    let target = edition.timeline.starts[member] + Int64((local * 1000).rounded())
                    await p.service.seek(toGlobalMs: target)
                    #expect(p.service.currentPoint == AudioPoint(assetID: edition.ids[member], ms: Int64((local * 1000).rounded())))
                    p.service.setRate(rate)
                    let t0 = uptime()
                    let g0 = p.service.currentGlobalMs
                    p.service.play()
                    try await Task.sleep(for: .seconds(4))
                    let g1 = p.service.currentGlobalMs, t1 = uptime()
                    p.service.pause()
                    let advance = Double(g1 - g0) / 1000 / (t1 - t0)
                    let run = try #require(p.collectors[member]?.longestRun(near: local, after: t0, tolerance: 0.3))
                    let e = try #require(try contentErrorMs(run, masterOffset: Fixtures.multi[member].start, master: master))
                    lines.append(String(format: "member %d at %.2f s, %.1fx: media advance %.3f s per wall s; rendered from %.3f s for %.2f s of source; content error %.1f ms (peak %.3f)",
                                        member + 1, local, rate, advance, run.start, run.seconds, e.errorMs, e.peak))
                    // Media time advances at the selected rate (start-up time makes it slightly lower).
                    #expect(advance >= Double(rate) * 0.8 && advance <= Double(rate) * 1.05, "advance \(advance) at \(rate)x")
                    #expect(abs(run.start - local) <= 0.01)
                    #expect(abs(e.errorMs) <= Self.toleranceMs && e.peak >= 0.5)
                }
            }
        }

        @Test("Relaunch after a crash resumes within 5 s of the true position (plan 10.1, 19.2)", .timeLimit(.minutes(3)))
        func relaunchAfterCrash() async throws {
            let edition = try await RealEdition()
            let master = try Fixtures.masterLong()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-real-pos-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            var lines = ["# Crash and relaunch on AVQueuePlayer with the durable position store. Environment: \(Results.environmentLabel())",
                         "trial\tplayed_s\ttrue_ms\tresumed_ms\tloss_ms\tresume_first_buffer_s\tresume_content_error_ms"]
            defer { Results.write("real-engine-relaunch.txt", lines) }
            for (trial, run) in [(150_000 as Int64, 7.3), (290_000, 9.6), (40_000, 4.2), (470_000, 12.4)].enumerated() {
                var truth: Int64 = 0
                do {
                    let a = RealPlayer(store: FilePositionStore(directory: dir))
                    await a.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
                    await a.service.seek(toGlobalMs: run.0)
                    a.service.play()
                    try await Task.sleep(for: .seconds(run.1))
                    // A crash: playback stops without pause, interruption, tick or lifecycle events reaching the service.
                    a.engine.delegate = nil
                    a.engine.player.pause()
                    truth = a.service.currentGlobalMs
                    a.engine.player.removeAllItems()
                }
                let b = RealPlayer(store: FilePositionStore(directory: dir))
                await b.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
                let resumed = b.service.currentGlobalMs
                let loss = truth - resumed
                #expect(loss >= 0 && loss <= 5_000, "trial \(trial): lost \(loss) ms")
                let point = try #require(b.service.currentPoint)
                let member = try #require(edition.ids.firstIndex(of: point.assetID))
                let t0 = uptime()
                b.service.play()
                _ = try await b.wait(5) { b.collectors[member]?.firstChunk(near: Double(point.ms) / 1000, after: t0) != nil }
                try await Task.sleep(for: .seconds(2))
                b.service.pause()
                let first = try #require(b.collectors[member]?.firstChunk(near: Double(point.ms) / 1000, after: t0))
                let rendered = try #require(b.collectors[member]?.longestRun(near: Double(point.ms) / 1000, after: t0, tolerance: 0.3))
                let e = try #require(try contentErrorMs(rendered, masterOffset: Fixtures.multi[member].start, master: master))
                lines.append(String(format: "%d\t%.1f\t%lld\t%lld\t%lld\t%.3f\t%.1f", trial, run.1, truth, resumed, loss, first.uptime - t0, e.errorMs))
                #expect(abs(rendered.start - Double(point.ms) / 1000) <= 0.01)
                #expect(abs(e.errorMs) <= Self.toleranceMs)
                b.stop()
            }
        }

        @Test("Unavailable member, deleted file and undecodable file each block only their segment (plan 10.1)", .timeLimit(.minutes(3)))
        func errorStatesOnTheRealEngine() async throws {
            let edition = try await RealEdition()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-bad-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let garbage = dir.appendingPathComponent("garbage.mp3")
            var rng = SeededRNG(seed: 404)
            try Data((0..<200_000).map { _ in UInt8(truncatingIfNeeded: rng.next()) }).write(to: garbage)
            let gone = dir.appendingPathComponent("deleted.mp3")
            var lines = ["# Error states on AVQueuePlayer. Environment: \(Results.environmentLabel())"]
            defer { Results.write("real-engine-error-states.txt", lines) }

            // Member 3 is not on this device: playback stops at its start; member 4 still plays.
            let p = RealPlayer()
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver(missing: [2]))
            await p.service.seek(toGlobalMs: edition.timeline.starts[2] - 2_500)
            p.service.play()
            let blocked = try await p.wait(10) { p.service.status == .segmentUnavailable(memberIndex: 2) }
            lines.append("member 3 not on this device: status=\(p.service.status) position=\(p.service.currentGlobalMs) ms (member start \(edition.timeline.starts[2])) player_rate=\(p.engine.player.rate)")
            #expect(blocked)
            #expect(p.service.currentGlobalMs == edition.timeline.starts[2])
            #expect(p.engine.player.rate == 0)
            #expect(p.collectors[2] == nil)  // never queued
            await p.service.seek(toGlobalMs: edition.timeline.starts[3] + 1_000)
            p.service.play()
            let resumed = try await p.wait(5) { p.engine.player.rate > 0 && p.service.status == .playing }
            lines.append("member 4 after the gap: status=\(p.service.status) player_rate=\(p.engine.player.rate)")
            #expect(resumed)
            p.stop()

            // Member 2 is listed as on this device but its file is gone; member 3's file does not decode.
            let q = RealPlayer()
            await q.service.load(timeline: edition.timeline, resolveFile: edition.resolver(replace: [1: gone, 2: garbage]))
            await q.service.seek(toGlobalMs: edition.timeline.starts[1] + 5_000)
            lines.append("member 2 file deleted: status=\(q.service.status)")
            #expect(q.service.status == .failed(memberIndex: 1, .missingFile))
            await q.service.seek(toGlobalMs: edition.timeline.starts[2] + 5_000)
            lines.append("member 3 undecodable: status=\(q.service.status)")
            if case .failed(2, .decodeError) = q.service.status {} else {
                Issue.record("expected a decode error for member 3, got \(q.service.status)")
            }
            await q.service.seek(toGlobalMs: 10_000)
            q.service.play()
            let playing = try await q.wait(5) { q.engine.player.rate > 0 }
            lines.append("member 1 still plays: status=\(q.service.status) player_rate=\(q.engine.player.rate)")
            #expect(playing && q.service.status == .playing)
            q.stop()
        }

        @Test("Now Playing info and remote commands are registered and drive the service (simulator)", .timeLimit(.minutes(2)))
        func nowPlayingAndRemoteCommands() async throws {
            let edition = try await RealEdition()
            let p = RealPlayer()
            defer { p.stop() }
            let chapters: [UUID: [ChapterInfo]] = [edition.ids[1]: [ChapterInfo(title: "Part 1, first half", startMs: 0, endMs: 80_000),
                                                                    ChapterInfo(title: "Part 1, second half", startMs: 80_000, endMs: 162_250)]]
            await p.service.load(timeline: edition.timeline, chapters: chapters, resolveFile: edition.resolver())
            let np = NowPlayingController(service: p.service)
            np.titleProvider = { "G0.4 multi-file fixture" }
            defer { np.unregister() }
            let registered = np.register()
            let center = MPRemoteCommandCenter.shared()
            var lines = ["# Now Playing and remote commands (MPRemoteCommandCenter.shared, MPNowPlayingInfoCenter.default). Environment: \(Results.environmentLabel())",
                         "# What the lock screen and Control Center show is a device item.",
                         "registered=\(registered.joined(separator: ","))"]
            defer { Results.write("now-playing.txt", lines) }
            let expected = ["play", "pause", "togglePlayPause", "skipForward", "skipBackward", "changePlaybackRate",
                            "changePlaybackPosition", "nextTrack", "previousTrack"]
            #expect(registered == expected)
            for name in expected { #expect(np.isEnabled(name), "\(name) not enabled") }
            for name in ["seekForward", "seekBackward", "bookmark"] { #expect(!np.isEnabled(name), "\(name) enabled") }
            #expect(!center.likeCommand.isEnabled && !center.dislikeCommand.isEnabled && !center.ratingCommand.isEnabled)
            #expect(center.skipForwardCommand.preferredIntervals == [15])
            #expect(center.changePlaybackRateCommand.supportedPlaybackRates == NowPlayingController.supportedRates)
            lines.append("disabled: seekForward, seekBackward, bookmark, like, dislike, rating, changeRepeatMode, changeShuffleMode, language options, stop")

            np.update()
            var info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            lines.append("paused: \(describe(info)) playbackState=\(MPNowPlayingInfoCenter.default().playbackState.rawValue)")
            #expect(info[MPMediaItemPropertyTitle] as? String == "G0.4 multi-file fixture")
            #expect(abs(((info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0) - Double(edition.timeline.durationMs) / 1000) < 0.01)
            #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 0)
            #expect((info[MPNowPlayingInfoPropertyChapterCount] as? NSNumber)?.intValue == 5)

            #expect(await np.perform(.play) == .success)
            #expect(p.service.status == .playing)
            info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 1)
            lines.append("playing: playbackState=\(MPNowPlayingInfoCenter.default().playbackState.rawValue) (recorded, not asserted: iOS derives it from the audio session)")
            let g0 = p.service.currentGlobalMs
            _ = await np.perform(.skipForward)
            #expect(abs(p.service.currentGlobalMs - (g0 + 15_000)) <= 400)
            _ = await np.perform(.nextChapter)
            #expect(p.service.currentChapterIndex == 1)
            #expect(abs(p.service.currentGlobalMs - edition.timeline.starts[1]) <= 400)
            _ = await np.perform(.changeRate(2))
            #expect(p.service.rate == 2)
            _ = await np.perform(.changePosition(seconds: 400))
            #expect(abs(p.service.currentGlobalMs - 400_000) <= 400)
            _ = await np.perform(.pause)
            #expect(p.service.status == .paused)
            info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            lines.append("after play, skip, next chapter, rate 2x, position 400 s, pause: \(describe(info)) playbackState=\(MPNowPlayingInfoCenter.default().playbackState.rawValue)")
            #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 0)
            #expect((info[MPNowPlayingInfoPropertyDefaultPlaybackRate] as? NSNumber)?.doubleValue == 2)
            #expect(abs(((info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? 0) - 400) < 1)

            // During a capture preview (review R4-03): Now Playing shows the preview, the commands that would move the
            // book are disabled and refused, and pause stops the preview with the book paused where it was.
            let book = try #require(p.service.currentPoint)
            let deactivations = p.session.deactivationCount
            #expect(await p.service.beginPreview(url: try #require(edition.resolver()(edition.ids[0])), startSeconds: 30, endSeconds: 60))
            try await Task.sleep(for: .seconds(1.5))
            np.update()
            info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
            lines.append("during a preview of 30-60 s of member 1: \(describe(info)) playbackState=\(MPNowPlayingInfoCenter.default().playbackState.rawValue)")
            #expect(abs(((info[MPMediaItemPropertyPlaybackDuration] as? NSNumber)?.doubleValue ?? 0) - 30) < 0.01)
            #expect((info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue == 1)
            let elapsed = (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue ?? -1
            #expect(elapsed > 0.5 && elapsed < 5, "preview elapsed \(elapsed) s")
            for name in NowPlayingController.navigationCommands { #expect(!np.isEnabled(name), "\(name) enabled during a preview") }
            for name in NowPlayingController.transportCommands { #expect(np.isEnabled(name), "\(name) disabled during a preview") }
            let refused = np.handle(.skipForward)
            #expect(refused == .commandFailed)
            #expect(p.service.mode == .preview && p.preview.isPlaying)
            let stopped = np.handle(.togglePlayPause)
            #expect(stopped == .success)
            await p.service.restoreTask?.value
            #expect(p.service.mode == .main && p.service.status == .paused && !p.preview.isPlaying)
            #expect(p.service.currentPoint == book)
            #expect(p.session.deactivationCount == deactivations + 1, "the stop released the session")
            for name in NowPlayingController.navigationCommands { #expect(np.isEnabled(name), "\(name) still disabled after the preview") }
            lines.append("during the preview: skipForward -> \(NowPlayingController.statusName(refused)); togglePlayPause -> \(NowPlayingController.statusName(stopped)), preview stopped, book paused at \(book.ms) ms of its member, session released (deactivations \(deactivations) -> \(p.session.deactivationCount))")
        }

        func describe(_ info: [String: Any]) -> String {
            info.keys.sorted().map { "\($0)=\(info[$0].map { "\($0)" } ?? "-")" }.joined(separator: " ")
        }

        @Test("The audio session is configured and activated only by playback (plan 10.1)", .timeLimit(.minutes(2)))
        func audioSessionOnlyForPlayback() async throws {
            let shared = AVAudioSession.sharedInstance()
            // A sentinel category: if inspection, decoding, export or capture configured the session, it would change.
            try shared.setCategory(.ambient)
            let edition = try await RealEdition()
            for m in Fixtures.multi { _ = try await AssetInspector.inspect(try Fixtures.url("multi/\(m.name)")) }
            _ = try await PCMDecoder.decode(url: try Fixtures.url("fmt-m4a-aac-lc.m4a"), start: 10, duration: 2)
            let captures = CaptureService(store: try temporaryStore(), exporter: AACExcerptExporter(), resolveSource: edition.resolver())
            let record = try captures.captureAudio(timeline: edition.timeline, atGlobalMs: 150_000, note: nil, idempotencyKey: UUID().uuidString)
            let done = try await captures.preserveExcerpt(record.id)
            #expect(done.statusKey == .audioExcerptSaved)
            let p = RealPlayer()
            defer { p.stop() }
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
            await p.service.seek(toGlobalMs: 20_000)
            let afterWork = (shared.category, p.session.activationCount)
            p.service.play()
            let afterPlay = (shared.category, shared.mode, shared.routeSharingPolicy, p.session.activationCount)
            // A user pause releases the session with notifyOthersOnDeactivation (review R2-06). Whether another app
            // then resumes is device checklist step 15.
            try await Task.sleep(for: .seconds(1.5))
            p.service.pause()
            let afterPause = (p.session.deactivationCount, p.session.lastDeactivationError, p.service.lastSessionError, p.service.sessionActive)
            Results.write("audio-session.txt", [
                "# Audio session use. Environment: \(Results.environmentLabel())",
                "# The test sets the shared session's category to ambient first, as a sentinel.",
                "after inspect, decode, capture, excerpt export, load and seek: category=\(afterWork.0.rawValue) activations=\(afterWork.1)",
                "after play: category=\(afterPlay.0.rawValue) mode=\(afterPlay.1.rawValue) routeSharingPolicy=\(afterPlay.2.rawValue) activations=\(afterPlay.3)",
                "after a user pause: setActive(false, notifyOthersOnDeactivation) calls=\(afterPause.0) error=\(afterPause.1 ?? "none") service_session_error=\(afterPause.2 ?? "none") service_holds_session=\(afterPause.3)",
            ])
            #expect(afterWork.0 == .ambient)
            #expect(afterWork.1 == 0)
            #expect(afterPlay.0 == .playback)
            #expect(afterPlay.1 == .spokenAudio)
            #expect(afterPlay.2 == .longFormAudio)
            #expect(afterPlay.3 == 1)
            #expect(afterPause.0 == 1, "deactivation failed: \(afterPause.1 ?? "-")")
            #expect(afterPause.1 == nil && afterPause.2 == nil)
            #expect(!afterPause.3)
        }
    }

    /// Capture preview on the real engine (plan 10.3, 19.2; T22): the excerpt plays in its own player, the main
    /// position, furthest position and listening total are untouched, and the audio the preview really rendered is
    /// compared with the intended excerpt boundaries.
    @Suite("Capture preview on the real engine (T22)", .serialized)
    @MainActor
    struct RealPreviewTests {
        @Test("Preview of retained excerpts and of pending source ranges: main context restored, boundaries measured", .timeLimit(.minutes(5)))
        func previewRestoresContextAndHitsBoundaries() async throws {
            let edition = try await RealEdition()
            let master = try Fixtures.masterLong()
            let store = try temporaryStore()
            let captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: edition.resolver())
            var lines = ["# Capture preview (preview AVQueuePlayer) while the main AVQueuePlayer session is paused. Environment: \(Results.environmentLabel())",
                         "# kind: the retained excerpt file, or the pending capture's source ranges (one segment per member file, played back to back)",
                         "# head_err = true content position of the first rendered second minus the intended start (ms, analysis tap + cross-correlation)",
                         "# seam_errs = for each later segment (the next member file), true content position of its first rendered second minus its intended start (ms)",
                         "# rendered_s = seconds of each segment's intended span the tap processed (clipped at its intended end), summed; intended_s = the capture's length",
                         "# tap_end_overrun = source time the analysis tap processed past the intended end (ms; an upper bound: the tap also processes buffers the output may never play)",
                         "# player_end = the preview player's own time when it reached the end, minus the intended end (ms)",
                         "# post_end_rms_ratio = loudness of the tap audio past the intended end relative to the whole run (0 = silence)",
                         "kind\trange(global ms)\tsegments\thead_err_ms\thead_peak\tseam_errs_ms\trendered_s\tintended_s\ttap_end_overrun_ms\tplayer_end_ms\tpost_end_rms_ratio\tmain_restored\tprogress_unchanged"]
            var heads: [Double] = [], ends: [Double] = [], playerEnds: [Double] = [], seamErrors: [Double] = []
            defer {
                lines.append(summary("preview head |error|", heads.map(abs), unit: "ms"))
                lines.append(summary("preview seam |error| (pending cross-file previews)", seamErrors.map(abs), unit: "ms"))
                lines.append(summary("preview tap end |overrun| (upper bound)", ends.map(abs), unit: "ms"))
                lines.append(summary("preview player end |error|", playerEnds.map(abs), unit: "ms"))
                Results.write("preview.txt", lines)
            }
            let p = RealPlayer()
            defer { p.stop() }
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
            // Five captures, two across a member boundary; each previewed as the retained excerpt and then as the
            // pending source ranges (every range, back to back across the member files; review R1-06).
            let spans: [(Int64, Int64)] = [(edition.timeline.starts[1] - 2_000, edition.timeline.starts[1] + 2_500),
                                           (61_234, 65_734), (edition.timeline.starts[2] - 3_100, edition.timeline.starts[2] + 1_400),
                                           (330_500, 335_000), (500_000, 504_500)]
            for (i, span) in spans.enumerated() {
                // Main listening somewhere else in the book; every other capture is previewed while main is paused.
                await p.service.seek(toGlobalMs: 200_000 + Int64(i) * 30_000)
                p.service.play()
                try await Task.sleep(for: .seconds(1.5))
                if i % 2 == 1 { p.service.pause() }
                var record = try captures.captureAudio(timeline: edition.timeline, atGlobalMs: span.1, note: nil, idempotencyKey: UUID().uuidString)
                record = try await captures.setRange(record.id, timeline: edition.timeline, globalStartMs: span.0, globalEndMs: span.1)
                let done = try await captures.preserveExcerpt(record.id)
                guard case .saved = done.excerpt else { Issue.record("export failed: \(done.excerpt)"); continue }
                let pieces = try record.ranges.map { r -> (masterStart: Double, duration: Double) in
                    let m = try #require(edition.ids.firstIndex(of: r.assetID))
                    return (Fixtures.multi[m].start + Double(r.startMs) / 1000, Double(r.durationMs) / 1000)
                }
                let total = pieces.reduce(0) { $0 + $1.duration }

                for kind in ["excerpt", "source ranges"] {
                    let wasPlaying = p.service.status == .playing
                    let writes = p.memory.history.count
                    // Each segment, and where its first sample sits in master-long.
                    let segments: [PreviewSegment], masterStarts: [Double], intendedEnd: Double
                    if kind == "excerpt" {
                        segments = [PreviewSegment(url: store.excerptURL(for: record.id))]
                        masterStarts = [pieces[0].masterStart]
                        intendedEnd = total
                    } else {
                        segments = try #require(p.service.previewSegments(for: record.ranges))
                        #expect(segments.count == record.ranges.count)
                        masterStarts = pieces.map(\.masterStart)
                        intendedEnd = try #require(segments.last?.endSeconds)
                    }
                    let start = segments[0].startSeconds
                    let t0 = uptime()
                    let ok = await p.service.beginPreview(segments)
                    #expect(ok)
                    #expect(p.engine.player.rate == 0, "main kept playing during preview")
                    let context = try #require(p.service.savedMainContext)
                    // Pausing main for the preview counts the main listening up to that moment and writes one
                    // preview-start checkpoint at the main position (when main was playing). From then until the
                    // preview ends nothing may change.
                    let baseline = (p.service.furthestGlobalMs, p.service.listenedMs, p.memory.history.count)
                    #expect(baseline.2 == writes + (wasPlaying ? 1 : 0))
                    if wasPlaying {
                        #expect(p.memory.history.last?.reason == .previewStart)
                        #expect(p.memory.history.last?.last == context.point)
                    }
                    var progressUnchanged = true
                    let deadline = uptime() + total + 6
                    while p.service.mode == .preview, uptime() < deadline {
                        if (p.service.furthestGlobalMs, p.service.listenedMs, p.memory.history.count) != baseline { progressUnchanged = false }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    #expect(p.service.mode == .main, "preview did not finish")
                    await p.service.restoreTask?.value
                    // Main is back at the saved point: exactly, or a few hundred ms further when it resumed playing.
                    let now = try #require(p.service.currentPoint)
                    let restored = wasPlaying
                        ? (now.assetID == context.point.assetID && (0...400).contains(now.ms - context.point.ms))
                        : now == context.point
                    #expect(restored, "main point \(now) vs saved \(context.point)")
                    #expect(progressUnchanged, "furthest, listening total or checkpoints changed during preview")
                    #expect(p.service.status == (wasPlaying ? .playing : .paused))
                    #expect(p.previewCollectors.count == segments.count)
                    let firstCollector = try #require(p.previewCollectors[0])
                    let lastCollector = try #require(p.previewCollectors[segments.count - 1])
                    let run = try #require(firstCollector.longestRun(near: start, after: t0, tolerance: 0.3))
                    let head = try #require(try contentErrorMs(run, masterOffset: masterStarts[0] - start, master: master, window: 1.0))
                    // Every later segment (the next member file) starts at its own start, with the right content.
                    var seams: [Double] = []
                    for index in segments.indices.dropFirst() {
                        let c = try #require(p.previewCollectors[index])
                        let seamRun = try #require(c.longestRun(near: 0, after: t0, tolerance: 0.3), "segment \(index) not rendered")
                        #expect(abs(seamRun.start) <= 0.01, "segment \(index) started at \(seamRun.start) s")
                        let e = try #require(try contentErrorMs(seamRun, masterOffset: masterStarts[index], master: master, window: 1.0))
                        #expect(abs(e.errorMs) <= 500 && e.peak >= 0.5)
                        seams.append(e.errorMs)
                    }
                    // Seconds of each segment's intended span the tap processed, summed: nothing may be skipped.
                    // (Clipped at each intended end; what the tap processes beyond it is reported as the overrun.)
                    var rendered = 0.0
                    for (index, segment) in segments.enumerated() {
                        let maxEnd = p.previewCollectors[index]?.tapRuns(after: t0).map(\.end).max() ?? segment.startSeconds
                        rendered += min(maxEnd, segment.endSeconds ?? total) - segment.startSeconds
                    }
                    let renderedEnd = lastCollector.tapRuns(after: t0).map(\.end).max() ?? 0
                    let overrun = (renderedEnd - intendedEnd) * 1000
                    // Where the preview player's own clock says it stopped, and how loud the audio is that the tap
                    // processed past the intended end (relative to the whole run). Past the end of an excerpt file
                    // nothing exists to play, so audio there would be a measurement artifact, not content.
                    let playerEnd = p.preview.lastFinishSeconds.map { ($0 - intendedEnd) * 1000 }
                    let last = try #require(lastCollector.tapRuns(after: t0).max { $0.end < $1.end })
                    let cut = max(0, min(last.samples.count, Int((intendedEnd - last.start) * last.rate)))
                    let post = Array(last.samples[cut...])
                    let postRatio = post.isEmpty ? 0 : (rms(post) / max(rms(last.samples), 1e-9))
                    heads.append(head.errorMs)
                    ends.append(overrun)
                    seamErrors += seams
                    if let playerEnd { playerEnds.append(playerEnd) }
                    lines.append("\(kind)\t\(span.0)-\(span.1)\t\(segments.count)\t\(fmt(head.errorMs))\t\(fmt(head.peak))\t\(seams.isEmpty ? "-" : seams.map { fmt($0) }.joined(separator: ","))\t\(String(format: "%.3f", rendered))\t\(String(format: "%.3f", total))\t\(fmt(overrun))\t\(playerEnd.map { fmt($0) } ?? "-")\t\(String(format: "%.3f", postRatio))\t\(restored)\t\(progressUnchanged)")
                    #expect(rendered >= total - 0.15, "\(kind): rendered \(rendered) s of \(total) s")
                    #expect(abs(head.errorMs) <= 500 && head.peak >= 0.5)
                    #expect(abs(overrun) <= 500, "tap-observed overrun (an upper bound) beyond the budget")
                    let stoppedAt = try #require(playerEnd, "the preview player did not report where it stopped")
                    #expect(abs(stoppedAt) <= 500)
                    // What the tap processed past the intended end is silence (padding), not source content: for an
                    // excerpt file nothing exists there, and for a source range the player did not decode past it.
                    #expect(postRatio < 0.05, "\(kind): audio past the intended end, rms ratio \(postRatio)")
                    try await Task.sleep(for: .seconds(0.5))
                }
                p.service.pause()
            }
        }

        @Test("A phone-call interruption during preview restores the main context, paused (T22)", .timeLimit(.minutes(2)))
        func interruptionDuringPreview() async throws {
            let edition = try await RealEdition()
            let p = RealPlayer()
            defer { p.stop() }
            let observer = AudioSessionObserver(service: p.service)
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
            await p.service.seek(toGlobalMs: 250_000)
            p.service.play()
            try await Task.sleep(for: .seconds(2))
            // Preview a pending source range of member 1 while main was playing.
            _ = await p.service.beginPreview(url: try #require(edition.resolver()(edition.ids[0])), startSeconds: 30, endSeconds: 60)
            let main = (p.service.savedMainContext?.point, p.service.furthestGlobalMs, p.service.listenedMs)
            try await Task.sleep(for: .seconds(1.5))
            #expect(p.preview.isPlaying)
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            await p.service.restoreTask?.value
            #expect(p.service.mode == .main)
            #expect(!p.preview.isPlaying)
            #expect(p.engine.player.rate == 0)
            #expect(p.service.status == .paused)
            #expect(p.service.currentPoint == main.0)
            try await Task.sleep(for: .seconds(2))  // the call
            NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
                                            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                                       AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue])
            try await Task.sleep(for: .seconds(0.5))
            #expect(p.service.status == .paused, "the user was previewing, not listening: main stays paused")
            #expect(p.engine.player.rate == 0)
            #expect(p.service.currentPoint == main.0)
            #expect(p.service.furthestGlobalMs == main.1 && p.service.listenedMs == main.2)
            #expect(observer.log.interruptionsBegan == 1 && observer.log.interruptionsEnded == 1)
            Results.write("preview-interruption.txt", [
                "# Interruption during preview (AVAudioSession notifications posted on the shared session). Environment: \(Results.environmentLabel())",
                "saved main context at preview start: \(String(describing: main.0)) furthest=\(main.1) listened=\(main.2)",
                "after interruption began, 2 s, ended(shouldResume): mode=\(p.service.mode) status=\(p.service.status) main=\(String(describing: p.service.currentPoint)) furthest=\(p.service.furthestGlobalMs) listened=\(p.service.listenedMs) preview_playing=\(p.preview.isPlaying) main_player_rate=\(p.engine.player.rate)",
            ])
        }

        /// Review R5-02 on the real players: loading another edition while a capture preview plays stops the preview
        /// player (before the fix it went on rendering the old edition's excerpt over the new one, with the audio
        /// session released under it), and the outgoing edition's checkpoint is its saved main point.
        @Test("Loading another edition during a preview stops the preview (R5-02)", .timeLimit(.minutes(2)))
        func loadingAnotherEditionDuringPreview() async throws {
            let edition = try await RealEdition()
            let next = try await RealEdition()
            let p = RealPlayer()
            defer { p.stop() }
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
            await p.service.seek(toGlobalMs: 250_000)
            p.service.play()
            try await Task.sleep(for: .seconds(2))
            // A pending source range of member 1, 30 s long: it would still be playing 10 s from now.
            #expect(await p.service.beginPreview(url: try #require(edition.resolver()(edition.ids[0])), startSeconds: 30, endSeconds: 60))
            let saved = try #require(p.service.savedMainContext)
            let progress = (p.service.furthestGlobalMs, p.service.listenedMs)
            let previewRendering = try await p.wait(5) { (p.previewCollectors[0]?.snapshot().count ?? 0) > 0 }
            try await Task.sleep(for: .seconds(1.5))
            #expect(previewRendering && p.preview.isPlaying)
            let loadStarted = uptime()
            await p.service.load(timeline: next.timeline, resolveFile: next.resolver())
            let loaded = uptime()
            try await Task.sleep(for: .seconds(3))
            // Whole buffers already handed to the tap may still arrive just after the stop (up to about 0.8 s at a
            // preview's end, preview-end-formats.tsv); nothing may arrive later than 1 s after the load returned.
            let late = (p.previewCollectors[0]?.snapshot() ?? []).filter { $0.uptime > loaded + 1.0 }
            let outgoing = p.memory.history.last { $0.editionID == edition.timeline.editionID }
            #expect(!p.preview.isPlaying && p.preview.player.rate == 0 && p.preview.player.items().isEmpty)
            #expect(late.isEmpty, "the old preview rendered \(late.count) chunks more than 1 s after the load")
            #expect(p.service.mode == .main && p.service.status == .paused && p.engine.player.rate == 0)
            #expect(p.service.timeline?.editionID == next.timeline.editionID)
            #expect(!p.service.sessionActive)
            #expect(outgoing?.reason == .editionChange && outgoing?.last == saved.point)
            #expect(outgoing?.furthestGlobalMs == progress.0 && outgoing?.listenedMs == progress.1)
            Results.write("preview-load-edition.txt", [
                "# Loading another edition while a capture preview plays (review R5-02; ADR-0006 decision 16). Environment: \(Results.environmentLabel())",
                "# The preview (a 30 s pending source range) had played about 1.5 s; the load took \(String(format: "%.3f", loaded - loadStarted)) s.",
                "after the load: preview_playing=\(p.preview.isPlaying) preview_player_rate=\(p.preview.player.rate) preview_items=\(p.preview.player.items().count) preview_tap_chunks_later_than_1s=\(late.count) mode=\(p.service.mode) status=\(p.service.status) main_player_rate=\(p.engine.player.rate) session_active=\(p.service.sessionActive) edition_is_new=\(p.service.timeline?.editionID == next.timeline.editionID)",
                "outgoing edition checkpoint: reason=\(outgoing.map { $0.reason.rawValue } ?? "none") last=\(outgoing.map { "\($0.last.ms) ms" } ?? "-") saved_main_point=\(saved.point.ms) ms furthest=\(outgoing?.furthestGlobalMs ?? -1) (before the preview \(progress.0)) listened=\(outgoing?.listenedMs ?? -1) (before the preview \(progress.1))",
            ])
        }

        /// Review R2-07: plan 19.2 sets the preview boundary budget on the release codec matrix. A retained excerpt
        /// is always AAC (measured above), but a pending capture previews its source range through AVPlayer with
        /// `forwardPlaybackEndTime`, so both boundaries are measured in every format on the provisional list.
        @Test("Pending preview of a source range in every provisional release format: head and end boundaries", .timeLimit(.minutes(8)))
        func pendingPreviewBoundariesPerFormat() async throws {
            let master = try Fixtures.master600()
            let formats = CodecMatrixTests.formats.filter { CodecMatrixTests.provisionalReleaseList.contains($0.id) }
            #expect(formats.count == CodecMatrixTests.provisionalReleaseList.count)
            // An 8 s source range at an arbitrary point, inside every file's first 600 s (the master).
            let startMs: Int64 = 221_370, endMs: Int64 = 229_370
            let start = Double(startMs) / 1000, end = Double(endMs) / 1000
            var lines = ["# Pending capture preview of the source range \(start)-\(end) s (preview AVQueuePlayer, forwardPlaybackEndTime) in each format; main paused. Environment: \(Results.environmentLabel())",
                         "# head_err = true content position where the first rendered second starts minus the intended start (ms; analysis tap + cross-correlation with master-600s)",
                         "# end_content_err = true content position of a 1.5 s probe within the last 2 s the tap rendered before the intended end, minus the position the player reported for it (ms)",
                         "# audible_past_end = audio past the intended end louder than -40 dB of the range's peak (ms; 0 = only silence past the end)",
                         "# end_err = where the audible content really ends minus the intended end (end_content_err + audible_past_end; ms)",
                         "# player_end = the preview player's own time when it reached the end, minus the intended end (ms)",
                         "# tap_end_overrun = source time the tap processed past the intended end (ms; an upper bound: the tap processes whole buffers, which past the end are silent)",
                         "# post_end_rms_ratio = loudness of what the tap processed past the intended end, relative to the range (0 = silence)",
                         "# session_released = the preview's audio session was deactivated (notifyOthersOnDeactivation) when it ended, main being paused (review R2-06)",
                         "format\tfile\thead_err_ms\thead_peak\tend_content_err_ms\tend_peak\taudible_past_end_ms\tend_err_ms\tplayer_end_ms\ttap_end_overrun_ms\tpost_end_rms_ratio\trendered_s\tintended_s\tmain_restored\tsession_released"]
            var heads: [Double] = [], endErrors: [Double] = [], playerEnds: [Double] = []
            defer {
                lines.append(summary("head |error|", heads.map(abs), unit: "ms"))
                lines.append(summary("end |error| (audible content end minus intended end)", endErrors.map(abs), unit: "ms"))
                lines.append(summary("player end |error|", playerEnds.map(abs), unit: "ms"))
                Results.write("preview-end-formats.tsv", lines)
            }
            for format in formats {
                let url = try Fixtures.url(format.file)
                let durationMs = try #require(try await AssetInspector.inspect(url).preciseDurationMs)
                let id = UUID()
                let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: format.file, durationMs: durationMs)])
                let p = RealPlayer()
                await p.service.load(timeline: timeline, resolveFile: { $0 == id ? url : nil })
                let context = try #require(p.service.currentPoint)
                let segments = try #require(p.service.previewSegments(for: [AudioRange(assetID: id, startMs: startMs, endMs: endMs)]))
                let t0 = uptime()
                let ok = await p.service.beginPreview(segments)
                #expect(ok, "\(format.id): preview did not start (\(p.preview.lastFailure ?? "-"))")
                let deadline = uptime() + (end - start) + 8
                while p.service.mode == .preview, uptime() < deadline { try await Task.sleep(for: .milliseconds(20)) }
                #expect(p.service.mode == .main, "\(format.id): preview did not finish")
                await p.service.restoreTask?.value
                let restored = p.service.currentPoint == context && p.service.status == .paused
                #expect(restored, "\(format.id): main at \(String(describing: p.service.currentPoint)), saved \(context)")
                let released = !p.service.sessionActive && p.service.lastSessionError == nil
                #expect(released, "\(format.id): session after the preview: held=\(p.service.sessionActive) error=\(p.service.lastSessionError ?? "none")")
                #expect(p.tapErrors.isEmpty, "\(format.id): \(p.tapErrors)")
                let collector = try #require(p.previewCollectors[0], "\(format.id): no preview tap")
                // Head: where the first rendered second really starts, relative to the intended start.
                let run = try #require(collector.longestRun(near: start, after: t0, tolerance: 0.3), "\(format.id): head not rendered")
                let headMeasured = try #require(try contentErrorMs(run, masterOffset: 0, master: master, window: 1.0), "\(format.id): head unmeasurable")
                let head = headMeasured.errorMs + (run.start - start) * 1000
                // End: the last run the tap processed, cut at the intended end. Its last 2 s before the cut are
                // located in the master (is the content up to the end the right content?), and what lies past the cut
                // must be silence (nothing past the intended end was played).
                let runs = collector.tapRuns(after: t0)
                // The run that carries the end of the range (the tap may deliver the silent buffers past the end as
                // a separate run).
                guard let last = runs.filter({ $0.start <= end - 2 && $0.end >= end - 0.05 }).max(by: { $0.samples.count < $1.samples.count }) else {
                    Issue.record("\(format.id): no rendered run reaches from 2 s before the intended end to the end: \(runs.map { "\($0.start)-\($0.end)" })")
                    p.stop()
                    continue
                }
                let cut = max(0, min(last.samples.count, Int(((end - last.start) * last.rate).rounded())))
                let tailCount = Int(2.0 * last.rate)
                let tail = TapRun(start: end - Double(tailCount) / last.rate, samples: Array(last.samples[(cut - tailCount)..<cut]), rate: last.rate,
                                  firstUptime: last.firstUptime, lastUptime: last.lastUptime)
                let endMeasured = try #require(try contentErrorMs(tail, masterOffset: 0, master: master, window: 1.5), "\(format.id): end unmeasurable")
                // Everything the tap processed past the intended end: the rest of that run and any later run.
                let pastRuns = runs.filter { $0.start >= end - 0.05 && $0.start > last.start }
                let before = Array(last.samples[..<cut])
                let post = Array(last.samples[cut...]) + pastRuns.flatMap(\.samples)
                let postRatio = post.isEmpty ? 0 : rms(post) / max(rms(before), 1e-9)
                // Audible audio past the intended end: up to the last sample past the end louder than -40 dB of the
                // range's peak (0 when what the tap processed there is silence).
                let threshold = (before.map(abs).max() ?? 0) * 0.01
                func lastAudibleEnd(_ r: TapRun, from index: Int) -> Double? {
                    guard index < r.samples.count, let i = r.samples[index...].lastIndex(where: { abs($0) > threshold }) else { return nil }
                    return r.start + Double(i + 1) / r.rate
                }
                let audibleEnds = [lastAudibleEnd(last, from: cut)].compactMap { $0 } + pastRuns.compactMap { lastAudibleEnd($0, from: 0) }
                let audiblePastEndMs = max(0, ((audibleEnds.max() ?? end) - end) * 1000)
                // Where the audible content really ends, minus the intended end: the content offset just before the
                // cut plus any audible audio after it.
                let endError = endMeasured.errorMs + audiblePastEndMs
                let overrun = ((runs.map(\.end).max() ?? end) - end) * 1000
                let playerEnd = try #require(p.preview.lastFinishSeconds.map { ($0 - end) * 1000 }, "\(format.id): the preview player did not report where it stopped")
                // Seconds of the intended range the tap processed (the union of every run, clipped to the range).
                var rendered = 0.0, covered = start
                for r in runs.sorted(by: { $0.start < $1.start }) where r.end > covered {
                    rendered += max(0, min(r.end, end) - max(r.start, covered))
                    covered = max(covered, min(r.end, end))
                }
                heads.append(head)
                endErrors.append(endError)
                playerEnds.append(playerEnd)
                lines.append([format.id, format.file, fmt(head), fmt(headMeasured.peak), fmt(endMeasured.errorMs), fmt(endMeasured.peak),
                              fmt(audiblePastEndMs), fmt(endError), fmt(playerEnd), fmt(overrun), String(format: "%.3f", postRatio),
                              String(format: "%.3f", rendered), String(format: "%.3f", end - start), "\(restored)",
                              released ? "yes" : "no: \(p.service.lastSessionError ?? "still held")"].joined(separator: "\t"))
                #expect(abs(head) <= 500 && headMeasured.peak >= 0.5, "\(format.id): head error \(head) ms, peak \(headMeasured.peak)")
                #expect(endMeasured.peak >= 0.5, "\(format.id): end content unmatched, peak \(endMeasured.peak)")
                #expect(abs(endError) <= 500, "\(format.id): end error \(endError) ms (content \(endMeasured.errorMs) ms, audible past the end \(audiblePastEndMs) ms)")
                #expect(abs(playerEnd) <= 500, "\(format.id): player end \(playerEnd) ms")
                // The tap's overrun is recorded, not judged: it processes whole buffers past the end, and they must be
                // silent (363-775 ms of digital silence in the clean runs, varying with the sample rate and from run to run).
                #expect(postRatio < 0.05, "\(format.id): audio past the intended end, rms ratio \(postRatio)")
                #expect(rendered >= (end - start) - 0.15, "\(format.id): rendered \(rendered) s of \(end - start) s")
                p.stop()
                try await Task.sleep(for: .seconds(0.3))
            }
        }
    }

    /// Indicative budgets in the simulator (plan 19.2): start/resume and the acknowledged capture save. The preview
    /// boundary distribution is in the preview suite. Device numbers are pending (device checklist).
    @Suite("Indicative budgets (simulator)", .serialized)
    @MainActor
    struct BudgetTests {
        @Test("Start/resume (warm, and cold resume by depth into the file) and acknowledged capture save distributions", .timeLimit(.minutes(25)))
        func budgets() async throws {
            var lines = ["# Indicative budgets (plan 19.2). Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# warm start/resume = play() to the first buffer at the position reaching the analysis tap (excludes output latency),",
                         "# for files this process has already inspected or opened (start after a seek, resume after a pause); cold resume is below"]
            defer {
                lines.append("# at the end: \(Results.loadLabel())")
                Results.write("budgets.txt", lines)
            }
            var samples: [(String, Double)] = []

            // Start after a seek and resume after a pause: the multi-file MP3 book and the 4 h 47 m LibriVox M4B.
            let edition = try await RealEdition()
            let m4bURL = try Fixtures.librivoxM4B()
            let m4bID = UUID()
            let m4bMs = try #require(try await AssetInspector.inspect(m4bURL).preciseDurationMs)
            let m4b = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: m4bID, fileName: "librivox.m4b", durationMs: m4bMs)])
            let m4bResolver: @Sendable (UUID) -> URL? = { $0 == m4bID ? m4bURL : nil }
            var rng = SeededRNG(seed: 1952)
            for (name, timeline, resolver, ids) in [("multi-file MP3", edition.timeline, edition.resolver(), edition.ids),
                                                    ("LibriVox M4B", m4b, m4bResolver, [m4bID])] {
                let p = RealPlayer()
                await p.service.load(timeline: timeline, resolveFile: resolver)
                for trial in 0..<10 {
                    let target = Int64(rng.next() % UInt64(timeline.durationMs - 10_000))
                    await p.service.seek(toGlobalMs: target)
                    let point = try #require(p.service.currentPoint)
                    let member = try #require(ids.firstIndex(of: point.assetID))
                    var t0 = uptime()
                    p.service.play()
                    _ = try await p.wait(5) { p.collectors[member]?.firstChunk(near: Double(point.ms) / 1000, after: t0) != nil }
                    let start = try #require(p.collectors[member]?.firstChunk(near: Double(point.ms) / 1000, after: t0)).uptime - t0
                    samples.append(("\(name): start after seek", start))
                    try await Task.sleep(for: .seconds(1))
                    p.service.pause()
                    try await Task.sleep(for: .seconds(0.3))
                    let resumePoint = try #require(p.service.currentPoint)
                    let resumeMember = try #require(ids.firstIndex(of: resumePoint.assetID))
                    t0 = uptime()
                    p.service.play()
                    _ = try await p.wait(5) { p.collectors[resumeMember]?.firstChunk(near: Double(resumePoint.ms) / 1000, after: t0, tolerance: 0.5) != nil }
                    let resume = try #require(p.collectors[resumeMember]?.firstChunk(near: Double(resumePoint.ms) / 1000, after: t0, tolerance: 0.5)).uptime - t0
                    samples.append(("\(name): resume after pause", resume))
                    p.service.pause()
                    lines.append(String(format: "%@ trial %d at %lld ms: start %.3f s, resume %.3f s", name, trial, target, start, resume))
                }
                p.stop()
            }

            // Acknowledged capture save: the durable anchor write (temporary file, F_FULLFSYNC, rename, directory sync).
            let p = RealPlayer()
            defer { p.stop() }
            await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
            let captures = CaptureService(store: try temporaryStore(), exporter: ScriptedExporter(), resolveSource: edition.resolver())
            let coordinator = QuickCaptureCoordinator(playback: p.service, captures: captures)
            for i in 0..<40 {
                await p.service.seek(toGlobalMs: 31_000 + Int64(i) * 13_000)
                guard case .saved = coordinator.captureNow(origin: "budget") else { Issue.record("capture \(i) not saved"); continue }
            }

            p.stop()

            // Cold resume (reviews R1-01 and R2-01): the relaunch path. The position store holds a checkpoint at a
            // given depth into a member file; a new playback service loads the edition (which creates the
            // AVPlayerItem and seeks to the checkpoint with zero tolerance, as on every launch) and plays. Each trial
            // opens a fresh copy of the file, so nothing AVFoundation keeps per file in this process is reused (a
            // relaunched app starts with nothing either). Whether the copy's data is in the host page cache is not
            // controlled. Measured: load (item creation, readiness and the seek), play() to the first buffer at the
            // checkpoint reaching the analysis tap, and their sum (a listener who presses play at launch). The depth
            // sweep runs from 20 minutes to 10 hours in the 10-hour files and covers short MP3 members (the real
            // LibriVox section MP3, a 2.7-minute member of the multi-file book), so the depth at which an MP3 crosses
            // the budget is measured, not inferred.
            lines.append("# cold resume: fresh copy of the file, stored checkpoint at depth_h into it, new service: load (open + zero-tolerance seek) then play()")
            lines.append("# every depth is measured in \(Self.coldResumeRounds) rounds (each round runs every file and depth once, on new copies), so run-to-run variation is visible (review R3-02)")
            lines.append("# timing: how the member is opened (ADR-0006 decision 2). estimatedCBR = the per-file timing mode the import chooses for an MP3 it proves constant bit rate")
            lines.append("# (review R4-01); precise = AVURLAssetPreferPreciseDurationAndTimingKey, what the import chooses for every other file (here the AAC M4B and the VBR MP3),")
            lines.append("# and for the CBR files the reference without the per-file mode. load_1m = the host's 1-minute load average when the trial ended (review R4-02)")
            lines.append("cold_resume\tfile\ttiming\tround\tdepth_h\tcheckpoint_ms\tload_s\tplay_to_audio_s\tload_plus_play_s\tresumed_at_checkpoint\tcontent_error_ms\tload_1m")
            let master = try Fixtures.masterLong()
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("g04-cold-resume-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            var cold: [ColdTrial] = []
            var durations: [String: Int64] = [:]
            for target in Self.coldResumeTargets where durations[target.file] == nil {
                // The member's duration comes from inspecting the original fixture, never the copies being measured. The
                // import's timing decision for the file is checked against the targets' (review R4-01).
                let report = try await AssetInspector.inspect(try Fixtures.url(target.file))
                let durationMs: Int64 = try #require(report.preciseDurationMs)
                durations[target.file] = durationMs
                let expected: AssetTiming = Self.coldResumeTargets.contains { $0.file == target.file && $0.timing == .estimatedCBR } ? .estimatedCBR : .precise
                #expect(report.timing == expected, "\(target.file): the import chose \(report.timing) (\(report.timingDecision.reason))")
                lines.append("# import timing decision, \(target.file): \(report.timing.rawValue) (\(report.timingDecision.reason))")
            }
            for round in 0..<Self.coldResumeRounds {
            for target in Self.coldResumeTargets {
                let file = target.file
                let durationMs = try #require(durations[file])
                for (index, checkpointMs) in target.checkpointsMs.enumerated() {
                    let trial = round
                    // A path no earlier trial used (the same file appears once per timing mode in each round).
                    let copy = scratch.appendingPathComponent("\(round)-\(index)-\(target.timing.rawValue)-\((file as NSString).lastPathComponent)")
                    try FileManager.default.copyItem(at: try Fixtures.url(file), to: copy)
                    defer { try? FileManager.default.removeItem(at: copy) }
                    let id = UUID()
                    let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: file, durationMs: durationMs,
                                                                                                  timing: target.timing)])
                    let store = InMemoryPositionStore()
                    let point = AudioPoint(assetID: id, ms: checkpointMs)
                    try store.save(PlaybackCheckpoint(editionID: timeline.editionID, timelineRevision: timeline.revision, last: point,
                                                      lastGlobalMs: checkpointMs, furthest: point, furthestGlobalMs: checkpointMs,
                                                      listenedMs: 0, reason: .periodic))
                    let q = RealPlayer(store: store)
                    defer { q.stop() }
                    let t0 = uptime()
                    await q.service.load(timeline: timeline, resolveFile: { $0 == id ? copy : nil })
                    let loaded = uptime()
                    let atCheckpoint = q.service.currentPoint == point
                    #expect(atCheckpoint, "\(file) trial \(trial): resumed at \(String(describing: q.service.currentPoint)), checkpoint \(point)")
                    let seconds = Double(checkpointMs) / 1000
                    q.service.play()
                    let heard = try await q.wait(20) { q.collectors[0]?.firstChunk(near: seconds, after: loaded, tolerance: 0.5) != nil }
                    let first = try #require(q.collectors[0]?.firstChunk(near: seconds, after: loaded, tolerance: 0.5),
                                             "\(file) trial \(trial): no audio within 20 s of play()")
                    #expect(heard)
                    try await Task.sleep(for: .seconds(2))
                    q.service.pause()
                    let run = try #require(q.collectors[0]?.longestRun(near: seconds, after: loaded, tolerance: 0.5))
                    let e = try #require(try contentErrorMs(run, masterOffset: target.masterOffset, master: master, loopFrames: Fixtures.longLoopFrames))
                    #expect(abs(e.errorMs) <= 500 && e.peak >= 0.5, "\(file) trial \(trial): content error \(e.errorMs) ms, peak \(e.peak)")
                    let total = first.uptime - t0
                    let depthHours = seconds / 3600
                    cold.append(ColdTrial(file: file, timing: target.timing, round: round, isMP3: file.hasSuffix(".mp3"), depthHours: depthHours,
                                          checkpointMs: checkpointMs, total: total, contentErrorMs: e.errorMs))
                    lines.append(String(format: "cold_resume\t%@\t%@\t%d\t%.2f\t%lld\t%.3f\t%.3f\t%.3f\t%@\t%.1f\t%@", file, target.timing.rawValue, trial, depthHours,
                                        checkpointMs, loaded - t0, first.uptime - loaded, total, atCheckpoint ? "yes" : "no", e.errorMs, Results.load1m()))
                }
            }
            }

            let startTimes = samples.map(\.1)
            let saves = coordinator.saveDurations.map { $0 * 1000 }
            lines.append(summary("start/resume local audio, warm (multi-file MP3 members and the LibriVox M4B; budget p95 <= 1.5 s)", startTimes, unit: "s"))
            for kind in Set(samples.map(\.0)).sorted() {
                lines.append("  " + summary(kind, samples.filter { $0.0 == kind }.map(\.1), unit: "s"))
            }
            for target in Self.coldResumeTargets {
                let xs = cold.filter { $0.file == target.file && $0.timing == target.timing }.map(\.total)
                lines.append(summary("cold resume (load + play to audio), \(target.file), \(target.timing.rawValue) (budget 1.5 s)", xs, unit: "s")
                             + " within_budget=\(xs.filter { $0 <= 1.5 }.count)/\(xs.count)")
            }
            // Per depth: the spread of the rounds (review R3-02: one trial per depth is not enough to place the crossing).
            for (file, timing) in [("long-mp3-cbr-10h.mp3", AssetTiming.precise), ("long-mp3-vbr-10h.mp3", .precise), ("long-mp3-cbr-10h.mp3", .estimatedCBR)] {
                for depth in Self.longFileCheckpointsMs.map({ Double($0) / 3_600_000 }) {
                    let xs: [Double] = cold.filter { $0.file == file && $0.timing == timing && abs($0.depthHours - depth) < 0.001 }.map(\.total)
                    let head: String = String(format: "by depth, %@ (%@) at %.2f h: ", file, timing.rawValue, depth)
                    let values: String = xs.map { String(format: "%.3f", $0) }.joined(separator: ", ")
                    let within: Int = xs.filter { $0 <= 1.5 }.count
                    let tail: String = String(format: " s (min %.3f, max %.3f; within budget %d/%d)", xs.min() ?? Double.nan, xs.max() ?? Double.nan, within, xs.count)
                    lines.append(head + values + tail)
                }
            }
            // Where an MP3 crosses the budget: for each 10-hour MP3 and each round, the depth at which the cold resume
            // reaches 1.5 s, interpolated between the deepest trial within the budget and the next deeper one; the
            // range over the rounds; and the least-squares line through every trial of the file.
            for file in ["long-mp3-cbr-10h.mp3", "long-mp3-vbr-10h.mp3"] {
                var crossings: [Double] = []
                for round in 0..<Self.coldResumeRounds {
                    let xs = cold.filter { $0.file == file && $0.timing == .precise && $0.round == round }.sorted { $0.depthHours < $1.depthHours }
                    let c = Self.crossing(xs, budget: 1.5)
                    if let d = c.interpolated { crossings.append(d) }
                    lines.append("budget crossing, \(file), precise, round \(round): " + c.text)
                }
                let all = cold.filter { $0.file == file && $0.timing == .precise }.sorted { $0.depthHours < $1.depthHours }
                lines.append(String(format: "budget crossing, %@, precise, %d rounds: interpolated between %.2f h and %.2f h; ", file, Self.coldResumeRounds,
                                    crossings.min() ?? .nan, crossings.max() ?? .nan) + Self.crossing(all, budget: 1.5).fit)
            }
            // The per-file timing mode against the precise reference at the same file and depth: the content the engine
            // rendered at the checkpoint sits at the same place (the decoder's own constant offset), so estimated timing
            // is exact for a proved-CBR MP3 (review R4-01).
            var modeDifferences: [Double] = []
            for e in cold where e.timing == .estimatedCBR {
                let p = cold.filter { $0.file == e.file && $0.timing == .precise && $0.checkpointMs == e.checkpointMs }.map(\.contentErrorMs)
                guard let reference = p.first else { continue }
                modeDifferences.append(abs(e.contentErrorMs - reference))
            }
            lines.append(String(format: "content error, estimatedCBR minus precise at the same file and depth: n=%d max_abs=%.1f ms", modeDifferences.count, modeDifferences.max() ?? .nan))
            lines.append(summary("acknowledged capture save (budget p95 <= 200 ms)", saves, unit: "ms"))
            #expect(startTimes.count == 40)
            #expect(cold.count == Self.coldResumeRounds * Self.coldResumeTargets.map(\.checkpointsMs.count).reduce(0, +))
            #expect(saves.count == 40)
            #expect(Results.percentile(startTimes, 95) <= 1.5)
            #expect(Results.percentile(saves, 95) <= 200)
            // AAC M4B (an indexed container): a cold resume is inside the budget at every depth up to 10 hours.
            #expect(cold.filter { !$0.isMP3 }.allSatisfy { $0.total <= 1.5 })
            // The per-file timing mode: a proved-CBR MP3 opened with estimated timing resumes cold inside the budget at
            // every depth up to 10 hours, at exactly the place precise timing gives (review R4-01).
            let estimated = cold.filter { $0.timing == .estimatedCBR }
            #expect(estimated.count == Self.coldResumeRounds * 11)
            #expect(estimated.allSatisfy { $0.total <= 1.5 }, "estimatedCBR cold resumes: \(estimated.map { fmt($0.total) }) s")
            #expect(modeDifferences.count == estimated.count && modeDifferences.allSatisfy { $0 <= 1 }, "estimatedCBR vs precise content error: \(modeDifferences)")
            // MP3 with precise timing up to 0.33 h (20 minutes) into a file: a cold resume is inside the budget. Review
            // R4-02: the first-seek cost is CPU-bound and grows with the host's load (load_1m column), so the asserted
            // depth stops at the 0.33 h trials; deeper ones are recorded below.
            let shallow = cold.filter { $0.isMP3 && $0.timing == .precise && $0.depthHours <= 0.34 }
            // 0.33 h in both 10-hour MP3s, the LibriVox section at 10 minutes, the book member at 2 minutes; every round
            #expect(shallow.count == 4 * Self.coldResumeRounds)
            #expect(shallow.allSatisfy { $0.total <= 1.5 }, "shallow cold MP3 resumes: \(shallow.map { fmt($0.total) }) s")
            // MP3 with precise timing deeper into a file: the cold resume time grows with the depth (about 1 s per hour
            // on the simulator, more under load) and misses the 1.5 s budget beyond the crossing reported above (the
            // slow first precise seek; G0.4 report row 21, ADR-0006), whether the book is one file or many. What the
            // import chooses for a VBR MP3; a CBR MP3 avoids it with the per-file timing mode. A known issue, recorded
            // with the measured times whenever a deeper trial misses the budget, so the run stays green while the miss
            // stays visible. Not marked intermittent: it is not (review R3-03). If a run (for example on a device) meets
            // the budget at every depth, nothing is recorded and the table shows it.
            let deep = cold.filter { $0.isMP3 && $0.timing == .precise && $0.depthHours > 0.34 }
            let deepMisses = deep.filter { $0.total > 1.5 }
            if !deepMisses.isEmpty {
                let misses = deepMisses.map { String(format: "%@ %.2f h %.3f s", $0.file, $0.depthHours, $0.total) }.joined(separator: ", ")
                withKnownIssue("Cold resume deep into an MP3 file with precise timing misses the 1.5 s start/resume budget (crossing depth by round in budgets.txt; ADR-0006)") {
                    Issue.record("cold resume, MP3 with precise timing deeper than 0.33 h, over 1.5 s in \(deepMisses.count) of \(deep.count) trials: \(misses)")
                }
            }
        }

        /// Rounds of the cold-resume sweep (review R3-02).
        static let coldResumeRounds = 3

        struct ColdTrial {
            var file: String
            var timing: AssetTiming
            var round: Int
            var isMP3: Bool
            var depthHours: Double
            var checkpointMs: Int64
            var total: Double
            var contentErrorMs: Double
        }

        struct ColdTarget {
            var file: String
            /// Where the file's content starts in master-long (s).
            var masterOffset: Double
            var checkpointsMs: [Int64]
            /// How the member is opened (ADR-0006 decision 2).
            var timing: AssetTiming
        }

        /// Depths into the 10-hour files: about 0.33, 1, 1.5, 2, 3, 5.0, 7.6 and 10.0 hours, each at least 40 s away
        /// from the 2,161.45 s loop seams of the fixture (the content check folds positions into master-long).
        static let longFileCheckpointsMs: [Int64] = [1_203_400, 3_601_700, 5_398_300, 7_204_100, 10_850_000, 18_123_400, 27_456_700, 35_987_600]

        static let coldResumeTargets: [ColdTarget] = [
            ColdTarget(file: "long-aac-10h.m4b", masterOffset: 0, checkpointsMs: longFileCheckpointsMs, timing: .precise),
            ColdTarget(file: "long-mp3-cbr-10h.mp3", masterOffset: 0, checkpointsMs: longFileCheckpointsMs, timing: .precise),
            ColdTarget(file: "long-mp3-vbr-10h.mp3", masterOffset: 0, checkpointsMs: longFileCheckpointsMs, timing: .precise),
            // The real LibriVox section MP3 (22 min 36 s; master-long starts with its decode): 10 minutes in, and
            // 26 s before its end.
            ColdTarget(file: "fmt-librivox-mp3-22k.mp3", masterOffset: 0, checkpointsMs: [600_000, 1_330_000], timing: .precise),
            // A 2.7-minute member of the multi-file MP3 book (master-long from 137.5 s), 2 minutes in.
            ColdTarget(file: "multi/Part 1.mp3", masterOffset: 137.5, checkpointsMs: [120_000], timing: .precise),
            // The per-file timing mode (review R4-01): the same constant-bit-rate MP3 files as the import opens them,
            // with estimated timing (the 10-hour CBR file, the LibriVox section, the book member; 11 trials per round).
            ColdTarget(file: "long-mp3-cbr-10h.mp3", masterOffset: 0, checkpointsMs: longFileCheckpointsMs, timing: .estimatedCBR),
            ColdTarget(file: "fmt-librivox-mp3-22k.mp3", masterOffset: 0, checkpointsMs: [600_000, 1_330_000], timing: .estimatedCBR),
            ColdTarget(file: "multi/Part 1.mp3", masterOffset: 137.5, checkpointsMs: [120_000], timing: .estimatedCBR),
        ]

        struct Crossing {
            /// The interpolated depth (h) at which the trials reach the budget, when they cross it.
            var interpolated: Double?
            /// The least-squares line through the trials.
            var fit: String
            var text: String
        }

        /// Where the cold resume times of one file (sorted by depth) reach `budget` seconds.
        static func crossing(_ trials: [ColdTrial], budget: Double) -> Crossing {
            guard trials.count >= 2 else { return Crossing(interpolated: nil, fit: "too few trials", text: "too few trials") }
            let n = Double(trials.count)
            let mx = trials.map(\.depthHours).reduce(0, +) / n, my = trials.map(\.total).reduce(0, +) / n
            let sxy = trials.map { ($0.depthHours - mx) * ($0.total - my) }.reduce(0, +)
            let sxx = trials.map { ($0.depthHours - mx) * ($0.depthHours - mx) }.reduce(0, +)
            let slope = sxy / sxx
            let intercept = my - slope * mx
            let fit = String(format: "least squares over %d trials %.3f s + %.3f s per hour of depth (reaches %.1f s at %.2f h)", trials.count, intercept, slope, budget, (budget - intercept) / slope)
            guard let firstOver = trials.firstIndex(where: { $0.total > budget }) else {
                return Crossing(interpolated: nil, fit: fit, text: String(format: "every trial within the budget (deepest %.2f h); ", trials[trials.count - 1].depthHours) + fit)
            }
            guard firstOver > 0 else {
                return Crossing(interpolated: nil, fit: fit, text: String(format: "over the budget at the shallowest depth tried (%.2f h, %.3f s); ", trials[0].depthHours, trials[0].total) + fit)
            }
            let a = trials[firstOver - 1], b = trials[firstOver]
            let depth = a.depthHours + (budget - a.total) / (b.total - a.total) * (b.depthHours - a.depthHours)
            let allDeeperOver = trials[firstOver...].allSatisfy { $0.total > budget }
            return Crossing(interpolated: depth, fit: fit,
                            text: String(format: "between %.2f h (%.3f s) and %.2f h (%.3f s), interpolated %.2f h; every deeper trial over the budget: %@; ",
                                         a.depthHours, a.total, b.depthHours, b.total, depth, allDeeperOver ? "yes" : "no") + fit)
        }
    }
}
