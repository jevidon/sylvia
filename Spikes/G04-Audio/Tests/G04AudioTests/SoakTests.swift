import AVFoundation
import Darwin
import Foundation
import Testing
@testable import G04AudioKit

/// A durable position store that also remembers when each checkpoint was written (host uptime), so the soak can
/// check the checkpoint cadence in wall time and in media time.
@MainActor
final class TimedPositionStore: PositionStore {
    let inner: FilePositionStore
    private(set) var writes: [(uptime: TimeInterval, checkpoint: PlaybackCheckpoint)] = []
    init(directory: URL) { inner = FilePositionStore(directory: directory) }
    func save(_ checkpoint: PlaybackCheckpoint) throws {
        try inner.save(checkpoint)
        writes.append((ProcessInfo.processInfo.systemUptime, checkpoint))
    }
    func load(editionID: UUID) throws -> PlaybackCheckpoint? { try inner.load(editionID: editionID) }
}

/// The process's physical memory footprint in MB (`task_info` TASK_VM_INFO, the figure the system's memory limit
/// applies to), or nan when it cannot be read.
func physicalFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    // task_self_trap() instead of the mach_task_self_ global, which Swift 6 rejects as shared mutable state. It adds a
    // send-right reference per call; the soak calls it about 40 times, so the references are left in place.
    let task = task_self_trap()
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(task, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : .nan
}

extension RealAV {
    /// Sustained playback on the real engine (review R1-04; plan 10.1 "long files"; T18's logic on the simulator).
    /// Two hours of media at 3x (40 minutes of wall time) through the playback service on AVQueuePlayer: the last
    /// 45 minutes of the 10-hour VBR MP3, then across the member boundary into the 10-hour AAC M4B. Every minute it
    /// measures, from the audio the engine actually rendered, whether the content still matches the player's
    /// reported source time (cross-correlation with master-long), how far the analysis tap runs ahead of the player
    /// clock, and the process's memory footprint. At the end it checks the checkpoint cadence in wall and media time,
    /// the listening total, the last and furthest positions and the durable checkpoint. Whether the same holds for
    /// two hours on a locked phone is device checklist step 3 (T18).
    @Suite("Soak: two hours of media on the real engine", .serialized)
    @MainActor
    struct SoakTests {
        static let rate: Float = 3
        static let mediaSeconds: Double = 7_200
        static let firstMemberTailSeconds: Double = 2_700
        static let sampleEverySeconds: Double = 60

        @Test("Two hours of media at 3x across a member boundary: content, clock, checkpoints, memory", .timeLimit(.minutes(50)))
        func soak() async throws {
            let master = try Fixtures.masterLong()
            let files = ["long-mp3-vbr-10h.mp3", "long-aac-10h.m4b"]
            var members: [EditionMember] = [], urls: [UUID: URL] = [:]
            for file in files {
                let url = try Fixtures.url(file)
                let id = UUID()
                members.append(EditionMember(assetID: id, fileName: file, durationMs: try #require(try await AssetInspector.inspect(url).preciseDurationMs)))
                urls[id] = url
            }
            let timeline = try EditionTimeline(editionID: UUID(), members: members)
            let sources = urls
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-soak-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = TimedPositionStore(directory: dir)
            let p = RealPlayer(store: store)
            defer { p.stop() }

            var lines = ["# Soak: \(Int(Self.mediaSeconds / 60)) min of media at \(Self.rate)x on AVQueuePlayer through the playback service. Environment: \(Results.environmentLabel())",
                         "# edition: the last \(Int(Self.firstMemberTailSeconds)) s of \(files[0]), then \(files[1]) (both master-long looped, so content is checked against master-long)",
                         "# content_error_ms = true content position of the last 4 s the tap processed minus the source time the player reported for it (cross-correlation)",
                         "# tap_lead_s = source time of the newest audio the tap processed minus the player's current time (decoding ahead of output)",
                         "wall_s\tmember\tplayer_s\tglobal_ms\tcontent_error_ms\tpeak\ttap_lead_s\tfootprint_mb\tcheckpoints"]
            defer { Results.write("soak.txt", lines) }

            await p.service.load(timeline: timeline, resolveFile: { sources[$0] })
            let startGlobal = timeline.starts[1] - Int64(Self.firstMemberTailSeconds * 1000)
            await p.service.seek(toGlobalMs: startGlobal)
            p.service.setRate(Self.rate)
            let t0 = uptime()
            p.service.play()
            #expect(p.service.status == .playing)
            // The start is a cold seek deep into a 10-hour MP3, which is slow to produce audio (report row 21). Until
            // audio flows the position does not move, so nothing can be lost; the cadence checks start from there.
            let startSeconds = Double(startGlobal) / 1000
            _ = try await p.wait(30) { p.collectors[0]?.firstChunk(near: startSeconds, after: t0, tolerance: 0.5) != nil }
            let firstAudio = try #require(p.collectors[0]?.firstChunk(near: startSeconds, after: t0, tolerance: 0.5),
                                          "no audio within 30 s of play()").uptime
            let wallSeconds = Self.mediaSeconds / Double(Self.rate)
            var errors: [Double] = [], leads: [Double] = [], footprints: [(wall: Double, mb: Double)] = []
            var lastSample = t0
            while uptime() - t0 < wallSeconds {
                try await Task.sleep(for: .seconds(min(Self.sampleEverySeconds, max(0.1, wallSeconds - (uptime() - t0)))))
                let now = uptime()
                guard let member = p.engine.currentMemberIndex, let collector = p.collectors[member] else {
                    Issue.record("no current member at \(Int(now - t0)) s (status \(p.service.status))")
                    break
                }
                let playerSeconds = p.engine.currentSeconds
                let globalMs = p.service.currentGlobalMs
                // Only a snapshot is taken on the main actor, where the playback service and its ticks run; building
                // the runs and the cross-correlation happen off it, so the measurement never delays a checkpoint.
                let chunks = collector.snapshot(), rate = collector.sampleRate, since = lastSample
                for c in p.collectors.values { c.reset() }  // bound the analysis memory: keep only audio from now on
                lastSample = uptime()
                let footprint = physicalFootprintMB()
                footprints.append((now - t0, footprint))
                var cells = [String(format: "%.0f", now - t0), "\(member)", String(format: "%.3f", playerSeconds), "\(globalMs)"]
                let analysis = try await Task.detached { () throws -> (run: TapRun, error: (errorMs: Double, peak: Float)?)? in
                    guard let run = AudioTapCollector.runs(chunks, rate: rate, after: since).max(by: { $0.end < $1.end }),
                          run.seconds >= 4 else { return nil }
                    let keep = Int(4 * run.rate)
                    let tail = TapRun(start: run.end - Double(keep) / run.rate, samples: Array(run.samples.suffix(keep)), rate: run.rate,
                                      firstUptime: run.lastUptime, lastUptime: run.lastUptime)
                    return (run, try contentErrorMs(tail, masterOffset: 0, master: master, loopFrames: Fixtures.longLoopFrames))
                }.value
                if let analysis {
                    let run = analysis.run
                    let e = try #require(analysis.error, "content unmeasurable at \(Int(now - t0)) s")
                    errors.append(e.errorMs)
                    leads.append(run.end - playerSeconds)
                    #expect(abs(e.errorMs) <= RealServiceTests.toleranceMs && e.peak >= 0.5,
                            "at \(Int(now - t0)) s: content error \(e.errorMs) ms, peak \(e.peak)")
                    cells += [fmt(e.errorMs), fmt(e.peak), String(format: "%.3f", run.end - playerSeconds)]
                } else {
                    // Right after the member boundary the new member's collector may hold less than 4 s.
                    cells += ["-", "-", "-"]
                }
                cells += [String(format: "%.1f", footprint), "\(store.writes.count)"]
                lines.append(cells.joined(separator: "\t"))
            }
            let wall = uptime() - t0
            p.service.pause()
            // Wall time from the first audio to the pause: the listening total counts only wall time while the media
            // advanced, so the cold-seek stall before the first audio is not listening (review R2-02).
            let heardWall = uptime() - firstAudio
            let endGlobal = p.service.currentGlobalMs
            let media = Double(endGlobal - startGlobal) / 1000

            // Checkpoint cadence while playing: periodic and item-change writes between play and pause.
            let playing = store.writes.filter { $0.uptime >= t0 && [.periodic, .itemChange].contains($0.checkpoint.reason) }
            let wallGaps = zip(playing, playing.dropFirst()).map { $1.uptime - $0.uptime }
            let mediaGaps = zip(playing, playing.dropFirst()).map { Double($1.checkpoint.lastGlobalMs - $0.checkpoint.lastGlobalMs) }
            // The first checkpoint while playing, counted from the first audio (before it the position stands still).
            let firstAfterAudio = playing.first.map { $0.uptime - firstAudio } ?? .infinity
            let firstMediaMs = playing.first.map { Double($0.checkpoint.lastGlobalMs - startGlobal) } ?? .infinity
            let durable = try #require(try store.inner.load(editionID: timeline.editionID))
            let memoryGrowth = (footprints.last?.mb ?? .nan) - (footprints.first?.mb ?? .nan)

            lines.append(String(format: "played: wall %.1f s, media %.1f s (%.4f x wall), from %lld to %lld ms global", wall, media, media / wall, startGlobal, endGlobal))
            lines.append(summary("content error |ms| (each minute)", errors.map(abs), unit: "ms"))
            lines.append(summary("tap lead over the player clock", leads, unit: "s"))
            lines.append(String(format: "play() to first audio (cold seek into the 10-hour MP3): %.3f s", firstAudio - t0))
            lines.append(String(format: "checkpoints while playing: %d; wall gap max %.3f s; media gap max %.0f ms; first %.3f s after the first audio, %.0f ms of media after the start; item-change checkpoints naming member 2: %d",
                                playing.count, wallGaps.max() ?? .nan, mediaGaps.max() ?? .nan, firstAfterAudio, firstMediaMs,
                                playing.filter { $0.checkpoint.reason == .itemChange && $0.checkpoint.last.assetID == members[1].assetID }.count))
            lines.append("final: last_ms=\(endGlobal) durable_last_ms=\(durable.lastGlobalMs) furthest_ms=\(p.service.furthestGlobalMs) durable_furthest_ms=\(durable.furthestGlobalMs) listened_ms=\(p.service.listenedMs) durable_listened_ms=\(durable.listenedMs) durable_reason=\(durable.reason.rawValue)")
            lines.append(String(format: "listening total: %.1f s; wall time from play() %.1f s, from the first audio %.1f s (the stall before the first audio is not listening)",
                                Double(p.service.listenedMs) / 1000, wall, heardWall))
            lines.append(String(format: "memory footprint: first sample %.1f MB, last %.1f MB, max %.1f MB, growth %.1f MB", footprints.first?.mb ?? .nan,
                                footprints.last?.mb ?? .nan, footprints.map(\.mb).max() ?? .nan, memoryGrowth))

            // Media advanced at the selected rate with no stall (start-up and the member boundary cost a little).
            #expect(media / wall >= Double(Self.rate) * 0.97 && media / wall <= Double(Self.rate) * 1.01, "media \(media) s in \(wall) s")
            #expect(errors.count >= Int(wallSeconds / Self.sampleEverySeconds) - 2, "content measured \(errors.count) times")
            #expect(leads.allSatisfy { $0 >= 0 && $0 <= 3 }, "tap lead \(leads)")
            // Crash-loss budget (plan 19.2): never more than 5 s of book between durable checkpoints while playing.
            #expect(firstAfterAudio <= 5.5, "first checkpoint \(firstAfterAudio) s after the first audio")
            #expect(firstMediaMs <= 5_000, "first checkpoint \(firstMediaMs) ms of media after the start")
            #expect((wallGaps.max() ?? .infinity) <= 5.5)
            #expect((mediaGaps.max() ?? .infinity) <= 5_000)
            #expect(playing.contains { $0.checkpoint.reason == .itemChange && $0.checkpoint.last.assetID == members[1].assetID && $0.checkpoint.last.ms <= 1_000 })
            // The pause checkpoint is the durable state; listening time is wall time of main playback while the
            // media advanced, so it matches the wall time from the first audio, not from play().
            // AVPlayer's reported time can still move by a millisecond after pause() returns (seen in the second clean
            // run: durable 41216709 ms, read afterwards 41216710 ms), so the comparison allows 50 ms.
            #expect(durable.reason == .pause && abs(durable.lastGlobalMs - endGlobal) <= 50,
                    "durable \(durable.reason.rawValue) at \(durable.lastGlobalMs) ms, service at \(endGlobal) ms")
            #expect(abs(Double(p.service.listenedMs) / 1000 - heardWall) <= 2,
                    "listened \(p.service.listenedMs) ms; \(heardWall) s of wall time since the first audio")
            #expect(durable.listenedMs == p.service.listenedMs)
            // The soak started with a seek far ahead of the stored frontier (0): after sustained listening the
            // frontier follows it (ADR-0006 decision 9).
            #expect(abs(p.service.furthestGlobalMs - endGlobal) <= 5_000)
            #expect(durable.furthestGlobalMs == p.service.furthestGlobalMs)
            // No growth that would end a long session: under 64 MB between the first sample (after a minute) and
            // the end.
            #expect(memoryGrowth.isFinite && memoryGrowth <= 64, "footprint grew \(memoryGrowth) MB")
        }
    }
}
