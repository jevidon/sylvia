import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit
extension RealAV {
    /// Long files (plan 10.1 "test seeking ... with real devices and long files") and the real LibriVox M4B.
    /// The 10-hour fixtures are master-long.wav looped 17 times, so positions fold back into the master.
    @Suite("Long files and the LibriVox M4B", .serialized)
    @MainActor
    struct LongFileTests {
        static let loopSeconds = Double(Fixtures.longLoopFrames) / 44_100
        static let longDurationMs = Int64((Double(Fixtures.longLoopFrames * Fixtures.longLoops) / 44.1).rounded())
        static let points: [Double] = [3_601.3, 18_000.7, 30_123.4, 36_700.9]

        @Test func masterLongHasTheDocumentedLength() throws {
            #expect(try Fixtures.masterLong().frameCount == Fixtures.longLoopFrames)
        }

        @Test("10-hour AAC M4B and MP3: duration, chapters, seek, export, end of file", .timeLimit(.minutes(10)),
              arguments: ["long-aac-10h.m4b", "long-mp3-cbr-10h.mp3", "long-mp3-vbr-10h.mp3"])
        func longFile(_ file: String) async throws {
            let url = try Fixtures.url(file)
            let master = try Fixtures.masterLong()
            var lines = ["# \(file). Environment: \(Results.environmentLabel())"]
            defer { Results.write("long-\(file).txt", lines) }
            let report = try await AssetInspector.inspect(url)
            lines.append("playable=\(report.isPlayable) codec=\(report.codec ?? "-") precise_ms=\(report.preciseDurationMs ?? -1) estimated_ms=\(report.estimatedDurationMs ?? -1) chapters=\(report.chapters.count) source=\(report.chapterSource.rawValue) inspect_s=\(fmt(report.inspectSeconds))")
            #expect(report.isPlayable)
            let duration = try #require(report.preciseDurationMs)
            #expect(abs(duration - Self.longDurationMs) <= 500, "duration \(duration) vs \(Self.longDurationMs)")
            if file.hasSuffix(".m4b") {
                #expect(report.chapters.count == Fixtures.longLoops)
                for (i, c) in report.chapters.enumerated() {
                    let want = Int64((Double(i) * Self.loopSeconds * 1000).rounded())
                    #expect(abs(c.startMs - want) <= 50, "chapter \(i) at \(c.startMs) ms, expected \(want)")
                    #expect(c.title == "Loop \(i + 1)")
                }
            }

            for t in Self.points {
                let pcm = try await PCMDecoder.decode(url: url, start: t, duration: 4)
                let m = try #require(try TimingVerifier.measure(audio: pcm.samples, rate: pcm.sampleRate, intendedStart: t, master: master, loopFrames: Fixtures.longLoopFrames))
                lines.append("decoder_seek t=\(t) error_ms=\(fmt(m.errorMs)) peak=\(fmt(m.peak))")
                #expect(abs(m.errorMs) <= 500)
                #expect(m.peak >= 0.5)
            }

            let probe = PlayerProbe(url: url)
            #expect(try await probe.prepare())
            for t in [18_000.7, 36_700.9] {
                guard let r = try await probe.seekAndListen(to: t) else {
                    Issue.record("player seek \(t) s unmeasurable: \(probe.lastDiagnostic)")
                    lines.append("player_seek t=\(t) unmeasurable: \(probe.lastDiagnostic)")
                    continue
                }
                let m = try PlayerProbe.measure(r, reference: master, loopFrames: Fixtures.longLoopFrames)
                lines.append("player_seek t=\(t) start_offset_ms=\(m.startOffsetMs.map { fmt($0) } ?? "-") steady_clock_error_ms=\(m.steadyErrorMs.map { fmt($0) } ?? "-") (peak \(m.steadyPeak.map { fmt($0) } ?? "-")) first_buffer_error_ms=\(m.firstBufferErrorMs.map { fmt($0) } ?? "-") \(r.diagnostic)")
                #expect(abs(try #require(m.steadyErrorMs)) <= 500)
                #expect(abs(try #require(m.startOffsetMs)) <= 500)
            }
            // Play through the end of the 10-hour file.
            let ended = Task { @MainActor in
                for await _ in NotificationCenter.default.notifications(named: AVPlayerItem.didPlayToEndTimeNotification, object: probe.item) { return true }
                return false
            }
            _ = await probe.player.seek(to: CMTime(seconds: Double(duration) / 1000 - 2, preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
            probe.player.playImmediately(atRate: 1)
            // Cancelling the child (on timeout) cancels the observing task, which ends its notification loop.
            let reachedEnd = try await withTimeout(seconds: 15) {
                await withTaskCancellationHandler { await ended.value } onCancel: { ended.cancel() }
            }
            lines.append("played_to_end=\(reachedEnd ?? false)")
            #expect(reachedEnd == true)
            ended.cancel()
            probe.stop()

            // Excerpts near the end and across a loop seam (content continues from the start of the master).
            let seam = 16 * Self.loopSeconds
            for (s, e) in [(36_690.0, 36_720.0), (seam - 10, seam + 20)] {
                let seg = SourceSegment(url: url, range: AudioRange(assetID: UUID(), startMs: Int64(s * 1000), endMs: Int64(e * 1000)))
                let r = try await ExcerptProbe.run([seg], masterStart: s, masterEnd: e, master: master, loopFrames: Fixtures.longLoopFrames)
                lines.append("export \(s)-\(e) start_error_ms=\(fmt(r.startErrorMs)) end_error_ms=\(fmt(r.endErrorMs)) peaks=\(fmt(r.startPeak))/\(fmt(r.endPeak))")
                #expect(abs(r.startErrorMs) <= 500)
                #expect(abs(r.endErrorMs) <= 500)
            }
        }

        /// Seek-to-audio latency in long files, with and without AVURLAssetPreferPreciseDurationAndTimingKey. The
        /// precise option makes MP3 seeks exact but slow in a 10-hour file; this pins that negative result (plan 19.2:
        /// start/resume p95 1.5 s) so a change in either direction is noticed.
        @Test("Seek latency in 10-hour files: precise versus estimated timing", .timeLimit(.minutes(10)))
        func longSeekLatency() async throws {
            let master = try Fixtures.masterLong()
            var lines = ["# Seek-to-audio latency (play() to first tap buffer at the target). Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# Each probe opens a fresh copy of the file (a new file, so no state AVFoundation keeps per file is reused);",
                         "# whether the copy's data is in the host page cache is not controlled. prepare_s = AVPlayerItem creation to readyToPlay.",
                         "file\tprecise\tprepare_s\tpoint_s\tseek_call_s\tseek_to_audio_s\tstart_offset_ms\tsteady_clock_error_ms"]
            defer { Results.write("long-seek-latency.txt", lines) }
            var preciseMP3: [Double] = [], estimatedMP3Offsets: [Double] = [], aacLatency: [Double] = []
            var estimatedCBRLatency: [Double] = [], vbrPreciseOffsets: [Double] = [], vbrEstimatedOffsets: [Double] = []
            let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("g04-latency-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: scratch) }
            for file in ["long-aac-10h.m4b", "long-mp3-cbr-10h.mp3", "long-mp3-vbr-10h.mp3"] {
                for precise in [true, false] {
                    let copy = scratch.appendingPathComponent("\(precise ? "p" : "e")-\(file)")
                    try FileManager.default.copyItem(at: try Fixtures.url(file), to: copy)
                    defer { try? FileManager.default.removeItem(at: copy) }
                    let opened = uptime()
                    let probe = PlayerProbe(url: copy, precise: precise)
                    #expect(try await probe.prepare())
                    let prepare = uptime() - opened
                    for t in [12_345.6, 29_876.5] {
                        let r = try #require(try await probe.seekAndListen(to: t, listen: 2))
                        // A VBR MP3 without precise timing may land far from the target: search two minutes either way.
                        let radius = file.contains("vbr") && !precise ? 120.0 : 3.0
                        let m = try PlayerProbe.measure(r, reference: master, loopFrames: Fixtures.longLoopFrames, radiusSeconds: radius)
                        let latency = try #require(r.startLatency)
                        // An offset only counts when the content was found (peak); otherwise it is unmeasurable.
                        let found = (m.steadyPeak ?? 0) >= 0.5
                        lines.append("\(file)\t\(precise)\t\(fmt(prepare))\t\(t)\t\(fmt(r.seekSeconds))\t\(fmt(latency))\t\(found ? (m.startOffsetMs.map { fmt($0) } ?? "-") : "unmeasurable(peak \(m.steadyPeak.map { fmt($0) } ?? "-"), radius \(Int(radius)) s)")\t\(m.steadyErrorMs.map { fmt($0) } ?? "-")")
                        let offset = found ? abs(m.startOffsetMs ?? .infinity) : .infinity
                        if file.hasSuffix(".mp3") {
                            if precise { preciseMP3.append(latency) }
                            if file.contains("cbr"), !precise { estimatedMP3Offsets.append(offset); estimatedCBRLatency.append(latency) }
                            if file.contains("vbr") { if precise { vbrPreciseOffsets.append(offset) } else { vbrEstimatedOffsets.append(offset) } }
                        } else {
                            aacLatency.append(latency)
                            #expect(offset <= 500)
                        }
                    }
                    probe.stop()
                }
            }
            // AAC (indexed container): seeks start audio well inside the budget either way.
            #expect(aacLatency.allSatisfy { $0 < 1.5 })
            // MP3 with precise timing: exact position, but the first seek in an MP3 file the process has not read costs
            // about 1 s per hour of depth (review R2-01; deterministic on the simulator: every fresh copy here, at 3.4
            // and 8.3 h, took several seconds from play() to audio). Once the process has read the file, seeks take
            // about 0.2 s (the warm path; budgets.txt). A known issue, recorded with the measured times whenever a
            // seek misses the budget; not marked intermittent, because it is not (review R3-03). If a run (for
            // example on a device) meets the budget, nothing is recorded and the table shows it.
            let slowMP3 = preciseMP3.filter { $0 >= 1.5 }
            if !slowMP3.isEmpty {
                withKnownIssue("A first precise seek deep into a 10-hour MP3 exceeds the 1.5 s start budget (ADR-0006)") {
                    Issue.record("precise MP3 seek-to-audio \(preciseMP3.map { fmt($0) }) s; \(slowMP3.count) of \(preciseMP3.count) over 1.5 s")
                }
            }
            lines.append("precise_mp3_seek_to_audio_s=\(preciseMP3.map { fmt($0) }.joined(separator: ","))")
            // CBR MP3 without precise timing: fast and still on target (the frame size is constant).
            #expect(estimatedCBRLatency.allSatisfy { $0 < 1.5 })
            #expect(estimatedMP3Offsets.allSatisfy { $0 <= 500 })
            // VBR MP3: precise timing lands on target; estimated timing does not (the negative result that makes
            // precise timing mandatory for VBR MP3: ADR-0006 decision 2 opens only an MP3 the import proves constant
            // bit rate with estimated timing). Asserted so a change in AVFoundation is noticed.
            #expect(vbrPreciseOffsets.count == 2 && vbrPreciseOffsets.allSatisfy { $0 <= 500 })
            #expect(vbrEstimatedOffsets.contains { $0 > 500 }, "estimated timing in a 10-hour VBR MP3 was on target: \(vbrEstimatedOffsets)")
            lines.append("max_abs_start_offset_ms_estimated_cbr_mp3=\(estimatedMP3Offsets.max().map { fmt($0) } ?? "-")")
            lines.append("abs_start_offset_ms_estimated_vbr_mp3=\(vbrEstimatedOffsets.map { $0.isFinite ? fmt($0) : "unmeasurable" }.joined(separator: ","))")
            lines.append("abs_start_offset_ms_precise_vbr_mp3=\(vbrPreciseOffsets.map { $0.isFinite ? fmt($0) : "unmeasurable" }.joined(separator: ","))")
        }

        @Test("Real LibriVox M4B: chapters, duration, seek and export against a sequential decode", .timeLimit(.minutes(10)))
        func librivoxM4B() async throws {
            let url = try Fixtures.librivoxM4B()
            var lines = ["# MeditationsMarcusAurelius_librivox.m4b. Environment: \(Results.environmentLabel())"]
            defer { Results.write("librivox-m4b.txt", lines) }
            let report = try await AssetInspector.inspect(url)
            lines.append("playable=\(report.isPlayable) codec=\(report.codec ?? "-") rate=\(report.sampleRate ?? 0) precise_ms=\(report.preciseDurationMs ?? -1) chapters=\(report.chapters.count) source=\(report.chapterSource.rawValue)")
            for c in report.chapters { lines.append("chapter \(c.startMs)-\(c.endMs) \(c.title)") }
            #expect(report.isPlayable)
            #expect(report.chapters.count == 12)
            let duration = try #require(report.preciseDurationMs)
            #expect(abs(duration - 17_267_125) <= 500)
            #expect(zip(report.chapters, report.chapters.dropFirst()).allSatisfy { $0.startMs < $1.startMs })
            #expect(report.chapters.last.map { $0.endMs <= duration + 500 } == true)

            // Reference windows by sequential decode (sample counting from the start of the file).
            let points: [Double] = [1_000.5, 9_000.25, 17_000.75]
            let started = Date()
            let windows = try await SequentialReference.windows(url: url, points.map { ($0 - 40, 60) })
            lines.append("sequential_reference_decode_s=\(fmt(Date().timeIntervalSince(started)))")
            func reference(_ i: Int) -> ArrayPCMSource {
                ArrayPCMSource(samples: windows[i], originFrame: Int((points[i] - 40) * 44_100), sampleRate: 44_100)
            }
            for (i, t) in points.enumerated() {
                let pcm = try await PCMDecoder.decode(url: url, start: t, duration: 4)
                let m = try #require(try TimingVerifier.measure(audio: pcm.samples, rate: pcm.sampleRate, intendedStart: t, master: reference(i)))
                lines.append("decoder_seek t=\(t) error_ms=\(fmt(m.errorMs)) peak=\(fmt(m.peak))")
                #expect(abs(m.errorMs) <= 500)
                #expect(m.peak >= 0.9)
            }
            let probe = PlayerProbe(url: url)
            #expect(try await probe.prepare())
            let r = try #require(try await probe.seekAndListen(to: points[1]))
            probe.stop()
            let pm = try PlayerProbe.measure(r, reference: reference(1))
            lines.append("player_seek t=\(points[1]) start_offset_ms=\(pm.startOffsetMs.map { fmt($0) } ?? "-") steady_clock_error_ms=\(pm.steadyErrorMs.map { fmt($0) } ?? "-") \(r.diagnostic)")
            #expect(abs(try #require(pm.steadyErrorMs)) <= 500)
            #expect(abs(try #require(pm.startOffsetMs)) <= 500)

            let seg = SourceSegment(url: url, range: AudioRange(assetID: UUID(), startMs: 8_970_250, endMs: 9_000_250))
            let e = try await ExcerptProbe.run([seg], masterStart: 8_970.25, masterEnd: 9_000.25, master: reference(1))
            lines.append("export 8970.25-9000.25 start_error_ms=\(fmt(e.startErrorMs)) end_error_ms=\(fmt(e.endErrorMs)) peaks=\(fmt(e.startPeak))/\(fmt(e.endPeak))")
            #expect(abs(e.startErrorMs) <= 500)
            #expect(abs(e.endErrorMs) <= 500)
        }
    }
}

/// Runs `body`, returning nil if it does not finish within `seconds`.
func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async -> T) async throws -> T? {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask { try await Task.sleep(for: .seconds(seconds)); return nil }
        let first = try await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
