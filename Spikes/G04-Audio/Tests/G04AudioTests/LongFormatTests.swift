import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

extension RealAV {
    /// Review R3-01: every provisional release format as a long file (10 hours, and 3 hours for the formats whose
    /// open time grows with length), not only as a 10-minute file. Every file here is opened with precise timing, which
    /// ADR-0006 decision 2 requires for every file except an MP3 the import proves constant bit rate (that file's
    /// estimated timing is measured in PerFileTimingTests), and with it AVFoundation scans some containers when it
    /// opens them, in proportion to the file's length. Each measurement
    /// opens a fresh copy of the file (a new file, so nothing AVFoundation keeps per file in this process is reused,
    /// as after a relaunch); whether the copy's data is in the host page cache is not controlled. The 3- and 10-hour
    /// files are master-long.wav looped (Scripts/fixtures/generate-g04-audio-long-formats.sh), so positions fold back
    /// into master-long and timing is measured by cross-correlation.
    @Suite("Long files in every provisional format: open, cold resume, export, preview, remux (R3-01)", .serialized)
    @MainActor
    struct LongFormatTests {
        struct LongFile: Sendable {
            /// Codec matrix format id (`CodecMatrixTests.formats`).
            var format: String
            /// Relative to generated/g04-audio.
            var file: String
            /// Copies of master-long in the file; 0 for the 600 s matrix file.
            var loops: Int
            /// Chapters AVFoundation reports for the file (what the 10-minute matrix established for the container).
            var chapters: Int

            var expectedDurationMs: Int64 {
                loops == 0 ? 600_000 : Int64((Double(Fixtures.longLoopFrames * loops) / 44.1).rounded())
            }
            var hours: Double { Double(expectedDurationMs) / 3_600_000 }
        }

        /// Every provisional format at 600 s and 10.2 h (native FLAC and Ogg Opus also at 3.0 h). The AAC M4B and the
        /// two MP3 files with a Xing header are the main script's 10-hour files, measured here too so the table is
        /// complete; MP3 with ID3 CHAP is the CBR encode with a tag (its 10-hour equivalent is the CBR file), and the
        /// real LibriVox MP3 is 22 minutes long.
        static let openFiles: [LongFile] = [
            LongFile(format: "flac", file: "fmt-flac.flac", loops: 0, chapters: 4),
            LongFile(format: "flac", file: "long-formats/long-flac-3h.flac", loops: 5, chapters: 5),
            LongFile(format: "flac", file: "long-formats/long-flac-10h.flac", loops: 17, chapters: 17),
            LongFile(format: "ogg-opus", file: "fmt-opus.ogg", loops: 0, chapters: 4),
            LongFile(format: "ogg-opus", file: "long-formats/long-opus-3h.ogg", loops: 5, chapters: 5),
            LongFile(format: "ogg-opus", file: "long-formats/long-opus-10h.ogg", loops: 17, chapters: 17),
            LongFile(format: "opus-ext", file: "fmt-opus.opus", loops: 0, chapters: 4),
            LongFile(format: "opus-ext", file: "long-formats/long-opus-10h.opus", loops: 17, chapters: 17),
            LongFile(format: "mp4-flac", file: "fmt-mp4-flac.m4a", loops: 0, chapters: 4),
            LongFile(format: "mp4-flac", file: "long-formats/long-mp4-flac-10h.m4a", loops: 17, chapters: 17),
            LongFile(format: "mp4-opus", file: "fmt-mp4-opus.m4a", loops: 0, chapters: 4),
            LongFile(format: "mp4-opus", file: "long-formats/long-mp4-opus-10h.m4a", loops: 17, chapters: 17),
            LongFile(format: "caf-opus", file: "fmt-caf-opus.caf", loops: 0, chapters: 0),
            LongFile(format: "caf-opus", file: "long-formats/long-caf-opus-10h.caf", loops: 17, chapters: 0),
            LongFile(format: "wav", file: "fmt-wav.wav", loops: 0, chapters: 0),
            LongFile(format: "wav", file: "long-formats/long-wav-10h.wav", loops: 17, chapters: 0),
            LongFile(format: "m4a-alac", file: "fmt-m4a-alac.m4a", loops: 0, chapters: 4),
            LongFile(format: "m4a-alac", file: "long-formats/long-m4a-alac-10h.m4a", loops: 17, chapters: 17),
            LongFile(format: "m4a-he-aac-v1", file: "fmt-m4a-heaac-v1.m4a", loops: 0, chapters: 4),
            LongFile(format: "m4a-he-aac-v1", file: "long-formats/long-m4a-heaac-v1-10h.m4a", loops: 17, chapters: 17),
            LongFile(format: "m4a-he-aac-v2", file: "fmt-m4a-heaac-v2.m4a", loops: 0, chapters: 4),
            LongFile(format: "m4a-he-aac-v2", file: "long-formats/long-m4a-heaac-v2-10h.m4a", loops: 17, chapters: 17),
            LongFile(format: "m4a-aac-lc", file: "fmt-m4a-aac-lc.m4a", loops: 0, chapters: 4),
            LongFile(format: "m4a-aac-lc", file: "long-aac-10h.m4b", loops: 17, chapters: 17),
            LongFile(format: "mp3-cbr", file: "fmt-mp3-cbr.mp3", loops: 0, chapters: 0),
            LongFile(format: "mp3-cbr", file: "long-mp3-cbr-10h.mp3", loops: 17, chapters: 0),
            LongFile(format: "mp3-vbr-xing", file: "fmt-mp3-vbr-xing.mp3", loops: 0, chapters: 0),
            LongFile(format: "mp3-vbr-xing", file: "long-mp3-vbr-10h.mp3", loops: 17, chapters: 0),
            LongFile(format: "mp3-vbr-noxing", file: "fmt-mp3-vbr-noxing.mp3", loops: 0, chapters: 0),
            LongFile(format: "mp3-vbr-noxing", file: "long-formats/long-mp3-vbr-noxing-10h.mp3", loops: 17, chapters: 0),
        ]

        /// The 10-hour files of the formats the budget suite does not already resume cold by depth.
        static var coldResumeFiles: [LongFile] {
            openFiles.filter { $0.file.hasPrefix("long-formats/") && $0.loops == 17 }
        }

        /// Depths into the 10-hour files (0.33, 5.0 and 10.0 h), away from the loop seams.
        static let depthsMs: [Int64] = [1_203_400, 18_123_400, 35_987_600]

        /// Fresh copy of a fixture in `dir` (APFS clone: instant, but a new file to AVFoundation).
        static func freshCopy(_ relative: String, in dir: URL, tag: String) throws -> URL {
            let source = try Fixtures.url(relative)
            let copy = dir.appendingPathComponent("\(tag)-\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)")
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        }

        static func scratch(_ name: String) throws -> URL {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        /// Seconds from creating an AVPlayerItem for a new asset to `readyToPlay` (nil if it failed).
        static func itemReadySeconds(_ url: URL, precise: Bool) async throws -> Double? {
            let t0 = uptime()
            let asset = precise ? AssetInspector.preciseAsset(url) : AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            let player = TestAudio.player(item)
            defer { player.replaceCurrentItem(with: nil) }
            while item.status == .unknown { try await Task.sleep(for: .milliseconds(5)) }
            return item.status == .readyToPlay ? uptime() - t0 : nil
        }

        /// Precise opens per file: the open time of a long native FLAC, MP3 without a header or Ogg Opus file is
        /// what decides the length thresholds in ADR-0006, and a single trial can land in a host-load spike (review
        /// R5-05: in the round-5 review's run a 10-minute native FLAC took 2.65 s to open while the 1-minute load
        /// was 53-79), so each file is opened three times, each on its own fresh copy, with the host's load recorded
        /// per row.
        static let preciseOpenTrials = 3

        @Test("Open time against file length, per format (import inspection and AVPlayerItem readiness)", .timeLimit(.minutes(25)))
        func openTimeAgainstLength() async throws {
            var lines = ["# Open time against file length (review R3-01). Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# Every open on its own fresh copy of the file. inspect_s = AssetInspector.inspect (the import's first codec inspection: precise",
                         "# duration, tracks, chapters, tags); ready_precise_s = AVPlayerItem creation to readyToPlay with AVURLAssetPreferPreciseDurationAndTimingKey",
                         "# (the player opens every member this way on every launch, unless the import proved a constant-bit-rate MP3), the median of",
                         "# \(Self.preciseOpenTrials) trials listed in ready_precise_trials_s; ready_estimated_s = the same without the key (1 trial).",
                         "# Review R5-05: utc and load_1m_start/load_1m_end = the time and the host's 1-minute load average when the row's measurements began",
                         "# and ended (open times of the scanning formats grow with the host's load; host-load.tsv has the load every 30 s).",
                         "format\tfile\thours\tbytes\tinspect_s\tready_precise_s\tready_precise_trials_s\tready_estimated_s\tprecise_duration_ms\tduration_error_ms\tchapters\tutc\tload_1m_start\tload_1m_end"]
            var growth: [String] = []
            defer { Results.write("long-formats-open.tsv", lines + growth + ["# at the end: \(Results.loadLabel())"]) }
            let dir = try Self.scratch("open")
            defer { try? FileManager.default.removeItem(at: dir) }
            let clock = ISO8601DateFormatter()
            var readyByFormat: [String: [(hours: Double, seconds: Double)]] = [:]
            for f in Self.openFiles {
                let utc = clock.string(from: Date())
                let loadStart = Results.load1m()
                let a = try Self.freshCopy(f.file, in: dir, tag: "inspect")
                let report = try await AssetInspector.inspect(a)
                try? FileManager.default.removeItem(at: a)
                var preciseTrials: [Double?] = []
                for trial in 0..<Self.preciseOpenTrials {
                    let b = try Self.freshCopy(f.file, in: dir, tag: "precise\(trial)")
                    preciseTrials.append(try await Self.itemReadySeconds(b, precise: true))
                    try? FileManager.default.removeItem(at: b)
                }
                let c = try Self.freshCopy(f.file, in: dir, tag: "estimated")
                let estimated = try await Self.itemReadySeconds(c, precise: false)
                try? FileManager.default.removeItem(at: c)
                let loadEnd = Results.load1m()
                let opened = preciseTrials.compactMap { $0 }
                let precise: Double? = opened.count == preciseTrials.count ? Results.percentile(opened, 50) : nil
                let bytes = (try FileManager.default.attributesOfItem(atPath: try Fixtures.url(f.file).path)[.size] as? NSNumber)?.int64Value ?? 0
                let duration = report.preciseDurationMs ?? -1
                let error = duration - f.expectedDurationMs
                lines.append([f.format, f.file, String(format: "%.2f", f.hours), "\(bytes)", String(format: "%.3f", report.inspectSeconds),
                              precise.map { String(format: "%.3f", $0) } ?? "failed",
                              preciseTrials.map { $0.map { String(format: "%.3f", $0) } ?? "failed" }.joined(separator: ","),
                              estimated.map { String(format: "%.3f", $0) } ?? "failed",
                              "\(duration)", "\(error)", "\(report.chapters.count)", utc, loadStart, loadEnd].joined(separator: "\t"))
                #expect(report.isPlayable, "\(f.file) not playable")
                #expect(precise != nil, "\(f.file): a precise item failed to open")
                #expect(estimated != nil, "\(f.file): the estimated item failed to open")
                #expect(abs(error) <= 500, "\(f.file): precise duration \(duration) ms, expected \(f.expectedDurationMs)")
                #expect(report.chapters.count == f.chapters, "\(f.file): \(report.chapters.count) chapters, expected \(f.chapters)")
                if let precise { readyByFormat[f.format, default: []].append((f.hours, precise)) }
            }
            // Per format: the median precise open time of the longest file against the 600 s file, as seconds per hour
            // of file.
            growth.append("# precise open growth per format: (median ready_precise at the longest file - at 600 s) / (hours difference)")
            for (format, points) in readyByFormat.sorted(by: { $0.key < $1.key }) {
                guard let short = points.min(by: { $0.hours < $1.hours }), let long = points.max(by: { $0.hours < $1.hours }), long.hours > short.hours else { continue }
                let slope = (long.seconds - short.seconds) / (long.hours - short.hours)
                growth.append(String(format: "open_growth\t%@\t%.3f s per hour of file (%.3f s at %.2f h, %.3f s at %.2f h)", format, slope, short.seconds, short.hours, long.seconds, long.hours))
            }
        }

        @Test("Cold resume by depth through the playback service in every long format: preparing, never a decode error", .timeLimit(.minutes(25)))
        func coldResumeByDepth() async throws {
            let master = try Fixtures.masterLong()
            var lines = ["# Cold resume (review R3-01): fresh copy, stored checkpoint at depth_h, new service: load (open + zero-tolerance seek) then play().",
                         "# status_after_load must be paused (a slow open is .preparing while it lasts, never .failed). Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# load_1m = the host's 1-minute load average when the trial ended (review R4-02: open and first-seek times grow with the host's load)",
                         "cold_resume\tformat\tfile\ttrial\tdepth_h\tcheckpoint_ms\tload_s\tplay_to_audio_s\tload_plus_play_s\tsaw_preparing\tstatus_after_load\tcontent_error_ms\tload_1m"]
            var summaries: [String] = []
            defer { Results.write("long-formats-cold-resume.tsv", lines + summaries + ["# at the end: \(Results.loadLabel())"]) }
            let dir = try Self.scratch("cold")
            defer { try? FileManager.default.removeItem(at: dir) }
            var totals: [String: [Double]] = [:]
            for f in Self.coldResumeFiles {
                let durationMs = try #require(try await AssetInspector.inspect(try Fixtures.url(f.file)).preciseDurationMs)
                for trial in 0..<2 {
                    for checkpointMs in Self.depthsMs {
                        let copy = try Self.freshCopy(f.file, in: dir, tag: "cold\(trial)")
                        defer { try? FileManager.default.removeItem(at: copy) }
                        let r = try await Self.coldResume(copy, durationMs: durationMs, checkpointMs: checkpointMs, master: master, label: "\(f.file) trial \(trial)")
                        totals[f.format, default: []].append(r.total)
                        lines.append(String(format: "cold_resume\t%@\t%@\t%d\t%.2f\t%lld\t%.3f\t%.3f\t%.3f\t%@\t%@\t%.1f\t%@", f.format, f.file, trial,
                                            Double(checkpointMs) / 3_600_000, checkpointMs, r.load, r.playToAudio, r.total,
                                            r.sawPreparing ? "yes" : "no", "\(r.statusAfterLoad)", r.contentErrorMs, Results.load1m()))
                    }
                }
            }
            for (format, xs) in totals.sorted(by: { $0.key < $1.key }) {
                summaries.append(summary("cold resume (load + play to audio), \(format) 10 h (budget 1.5 s)", xs, unit: "s") + " within_budget=\(xs.filter { $0 <= 1.5 }.count)/\(xs.count)")
            }
            // The formats measured within the 1.5 s budget at every depth are asserted, so a regression is a failure.
            // The others (open time proportional to the file's length, or MP3's seek cost proportional to the depth)
            // are recorded as known issues with their numbers, only when they miss; G0.4 report row 21, ADR-0006.
            for (format, xs) in totals {
                if Self.withinBudgetAtTenHours.contains(format) {
                    #expect(xs.allSatisfy { $0 <= 1.5 }, "\(format): cold resume \(xs.map { fmt($0) }) s")
                } else if !xs.allSatisfy({ $0 <= 1.5 }) {
                    withKnownIssue("\(format): a cold resume in a 10-hour file misses the 1.5 s start/resume budget (ADR-0006, review R3-01)") {
                        Issue.record("\(format): cold resume \(xs.map { fmt($0) }) s")
                    }
                }
            }
        }

        /// Formats whose cold resume in a 10-hour file met the 1.5 s budget at every depth on the simulator (asserted).
        static let withinBudgetAtTenHours: Set<String> = ["mp4-flac", "mp4-opus", "caf-opus", "wav", "m4a-alac", "m4a-he-aac-v1", "m4a-he-aac-v2"]

        struct ColdResult {
            var load: Double
            var playToAudio: Double
            var total: Double
            var sawPreparing: Bool
            var statusAfterLoad: PlaybackService.Status
            var contentErrorMs: Double
        }

        /// The relaunch path on `copy`: a new service with a stored checkpoint loads the one-file edition and plays.
        static func coldResume(_ copy: URL, durationMs: Int64, checkpointMs: Int64, master: MasterPCM, label: String) async throws -> ColdResult {
            let id = UUID()
            let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: copy.lastPathComponent, durationMs: durationMs)])
            let store = InMemoryPositionStore()
            let point = AudioPoint(assetID: id, ms: checkpointMs)
            try store.save(PlaybackCheckpoint(editionID: timeline.editionID, timelineRevision: timeline.revision, last: point,
                                              lastGlobalMs: checkpointMs, furthest: point, furthestGlobalMs: checkpointMs, listenedMs: 0, reason: .periodic))
            let q = RealPlayer(store: store)
            defer { q.stop() }
            let t0 = uptime()
            let loading = Task { @MainActor in
                await q.service.load(timeline: timeline, resolveFile: { $0 == id ? copy : nil })
            }
            // Watch the status while the member opens (the load task and this loop share the main actor).
            var sawPreparing = false
            while q.service.status == .idle || q.service.isPreparing {
                if q.service.isPreparing { sawPreparing = true }
                try await Task.sleep(for: .milliseconds(10))
            }
            await loading.value
            let loaded = uptime()
            let status = q.service.status
            #expect(status == .paused, "\(label): status after load \(status)")
            #expect(q.service.currentPoint == point, "\(label): resumed at \(String(describing: q.service.currentPoint)), checkpoint \(point)")
            let seconds = Double(checkpointMs) / 1000
            q.service.play()
            let heard = try await q.wait(30) { q.collectors[0]?.firstChunk(near: seconds, after: loaded, tolerance: 0.5) != nil }
            let first = try #require(q.collectors[0]?.firstChunk(near: seconds, after: loaded, tolerance: 0.5), "\(label): no audio within 30 s of play()")
            #expect(heard)
            try await Task.sleep(for: .seconds(2))
            q.service.pause()
            let run = try #require(q.collectors[0]?.longestRun(near: seconds, after: loaded, tolerance: 0.5))
            let e = try #require(try contentErrorMs(run, masterOffset: 0, master: master, loopFrames: Fixtures.longLoopFrames), "\(label): unmeasurable")
            #expect(abs(e.errorMs) <= 500 && e.peak >= 0.5, "\(label): content error \(e.errorMs) ms, peak \(e.peak)")
            return ColdResult(load: loaded - t0, playToAudio: first.uptime - loaded, total: first.uptime - t0, sawPreparing: sawPreparing,
                              statusAfterLoad: status, contentErrorMs: e.errorMs)
        }

        @Test("Capture export and pending preview deep in every long format (cold): latency and boundaries", .timeLimit(.minutes(15)))
        func exportAndPreviewInLongFiles() async throws {
            let master = try Fixtures.masterLong()
            // The preceding 30 s at 9.5 h (away from the loop seams).
            let startMs: Int64 = 34_170_000, endMs: Int64 = 34_200_000
            let start = Double(startMs) / 1000, end = Double(endMs) / 1000
            var lines = ["# A capture of the preceding 30 s at \(end) s in each 10-hour file, on fresh copies (cold). export_s = the excerpt export (decode, AAC",
                         "# encode, durable write) as the capture transaction runs it after the anchor write; preview_start_s = beginPreview() of the pending",
                         "# source range (\(end - 8)-\(end) s) to its first buffer reaching the analysis tap. Errors against master-long by cross-correlation.",
                         "# Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "format\tfile\texport_s\texport_start_err_ms\texport_end_err_ms\tpreview_start_s\tpreview_head_err_ms\tload_1m"]
            var exports: [Double] = [], previews: [Double] = []
            defer {
                lines.append(summary("export of a 30 s excerpt 9.5 h into a 10-hour file, cold", exports, unit: "s"))
                lines.append(summary("pending preview start 9.5 h into a 10-hour file, cold", previews, unit: "s"))
                lines.append("# at the end: \(Results.loadLabel())")
                Results.write("long-formats-capture.tsv", lines)
            }
            let dir = try Self.scratch("capture")
            defer { try? FileManager.default.removeItem(at: dir) }
            // The main edition is a different file, so the preview's file is opened cold.
            let edition = try await RealEdition()
            for f in Self.openFiles where f.loops == 17 {
                let copy = try Self.freshCopy(f.file, in: dir, tag: "export")
                let seg = SourceSegment(url: copy, range: AudioRange(assetID: UUID(), startMs: startMs, endMs: endMs))
                let x = try await ExcerptProbe.run([seg], masterStart: start, masterEnd: end, master: master, loopFrames: Fixtures.longLoopFrames)
                try? FileManager.default.removeItem(at: copy)
                #expect(abs(x.startErrorMs) <= 500 && abs(x.endErrorMs) <= 500, "\(f.file): export errors \(x.startErrorMs)/\(x.endErrorMs) ms")

                let pcopy = try Self.freshCopy(f.file, in: dir, tag: "preview")
                defer { try? FileManager.default.removeItem(at: pcopy) }
                let p = RealPlayer()
                await p.service.load(timeline: edition.timeline, resolveFile: edition.resolver())
                let t0 = uptime()
                let ok = await p.service.beginPreview([PreviewSegment(url: pcopy, startSeconds: end - 8, endSeconds: end)])
                #expect(ok, "\(f.file): preview did not start (\(p.preview.lastFailure ?? "-"))")
                _ = try await p.wait(30) { p.previewCollectors[0]?.firstChunk(near: end - 8, after: t0, tolerance: 0.5) != nil }
                let firstChunk = p.previewCollectors[0]?.firstChunk(near: end - 8, after: t0, tolerance: 0.5)
                try await Task.sleep(for: .seconds(2))
                var head = Double.nan
                if let run = p.previewCollectors[0]?.longestRun(near: end - 8, after: t0, tolerance: 0.3),
                   let m = try contentErrorMs(run, masterOffset: 0, master: master, window: 1.0, loopFrames: Fixtures.longLoopFrames) {
                    head = m.errorMs + (run.start - (end - 8)) * 1000
                }
                p.service.endPreview(restoringPlayback: false)
                p.stop()
                let previewStart = firstChunk.map { $0.uptime - t0 }
                #expect(previewStart != nil, "\(f.file): no preview audio within 30 s")
                #expect(abs(head) <= 500, "\(f.file): preview head error \(head) ms")
                exports.append(x.exportSeconds)
                if let previewStart { previews.append(previewStart) }
                lines.append([f.format, f.file, String(format: "%.3f", x.exportSeconds), fmt(x.startErrorMs), fmt(x.endErrorMs),
                              previewStart.map { String(format: "%.3f", $0) } ?? "none", fmt(head), Results.load1m()].joined(separator: "\t"))
                try await Task.sleep(for: .seconds(0.3))
            }
        }

        /// The slow files and the container their packets are copied into (MPEG-4 refuses MP3 packets; CAF takes them).
        static let remuxTargets: [(file: String, container: ImportRemuxer.Container)] = [
            ("long-formats/long-flac-10h.flac", .mpeg4), ("long-formats/long-opus-10h.ogg", .mpeg4),
            ("long-formats/long-flac-3h.flac", .mpeg4), ("long-formats/long-opus-3h.ogg", .mpeg4),
            ("long-mp3-cbr-10h.mp3", .caf), ("long-mp3-vbr-10h.mp3", .caf), ("long-formats/long-mp3-vbr-noxing-10h.mp3", .caf),
        ]

        @Test("Mitigation: remux native FLAC and Ogg Opus into MPEG-4, and MP3 into CAF, at import; then open and resume cold", .timeLimit(.minutes(20)))
        func remuxMitigation() async throws {
            let master = try Fixtures.masterLong()
            var lines = ["# Remux at import (ImportRemuxer: the compressed packets copied unchanged, no decode; FLAC and Opus into .m4a, MP3 into .caf)",
                         "# of the files whose open or first deep seek is slow, then the remuxed copy opened and resumed cold like the originals.",
                         "# Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())"]
            defer { Results.write("long-formats-remux.tsv", lines + ["# at the end: \(Results.loadLabel())"]) }
            let dir = try Self.scratch("remux")
            defer { try? FileManager.default.removeItem(at: dir) }
            for (file, container) in Self.remuxTargets {
                let source = try Self.freshCopy(file, in: dir, tag: "source")
                defer { try? FileManager.default.removeItem(at: source) }
                let ext = container.fileExtension
                let remuxed = dir.appendingPathComponent("remuxed-\(UUID().uuidString.prefix(8)).\(ext)")
                defer { try? FileManager.default.removeItem(at: remuxed) }
                let loadStart = Results.load1m()
                let r = try await ImportRemuxer.remux(source, to: remuxed, container: container)
                let loadAfterRemux = Results.load1m()
                let sourceReport = try await AssetInspector.inspect(try Fixtures.url(file))
                let a = try Self.freshCopy(file, in: dir, tag: "ref")
                let sourceReady = try await Self.itemReadySeconds(a, precise: true)
                try? FileManager.default.removeItem(at: a)
                let report = try await AssetInspector.inspect(remuxed)
                let durationDiff = (report.preciseDurationMs ?? -1) - (sourceReport.preciseDurationMs ?? -2)
                // A fresh copy of the remuxed file for each cold measurement.
                let b = dir.appendingPathComponent("ready-\(UUID().uuidString.prefix(8)).\(ext)")
                try FileManager.default.copyItem(at: remuxed, to: b)
                let ready = try await Self.itemReadySeconds(b, precise: true)
                try? FileManager.default.removeItem(at: b)
                // load_1m: the host's 1-minute load average before the remux, after it, and after the open measurements
                // (review R5-05: remux and open times vary between runs with the host's load).
                lines.append(String(format: "remux\t%@\tinto %@\tsource %@\tremux_s=%.3f\tbytes=%lld (source %lld)\tsample_buffers=%d\tsource_ready_precise_s=%@\tremuxed_ready_precise_s=%@\tduration_ms=%lld (source %lld, diff %lld)\tchapters=%d (source %d; the importer keeps the source's)\tload_1m=%@,%@,%@",
                                    file, ext, r.sourceFormat, r.seconds, r.bytes,
                                    (try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber)?.int64Value ?? 0, r.sampleBuffers,
                                    sourceReady.map { String(format: "%.3f", $0) } ?? "failed", ready.map { String(format: "%.3f", $0) } ?? "failed",
                                    report.preciseDurationMs ?? -1, sourceReport.preciseDurationMs ?? -1, durationDiff,
                                    report.chapters.count, sourceReport.chapters.count, loadStart, loadAfterRemux, Results.load1m()))
                #expect(ready != nil, "\(file): remuxed copy failed to open")
                #expect(abs(durationDiff) <= 50, "\(file): remuxed duration differs by \(durationDiff) ms")
                // Decoder seeks in the remuxed copy against master-long, and the same windows decoded from the
                // source: the remux must not move content.
                let durationMs = try #require(report.preciseDurationMs)
                for t in [3_601.3, Double(durationMs) / 1000 - 400.7] {
                    let fromRemux = try await PCMDecoder.decode(url: remuxed, start: t, duration: 4)
                    let fromSource = try await PCMDecoder.decode(url: source, start: t, duration: 4)
                    let mr = try #require(try TimingVerifier.measure(audio: fromRemux.samples, rate: fromRemux.sampleRate, intendedStart: t, master: master, loopFrames: Fixtures.longLoopFrames))
                    let ms = try #require(try TimingVerifier.measure(audio: fromSource.samples, rate: fromSource.sampleRate, intendedStart: t, master: master, loopFrames: Fixtures.longLoopFrames))
                    let n = min(fromRemux.samples.count, fromSource.samples.count)
                    let maxDiff = zip(fromRemux.samples.prefix(n), fromSource.samples.prefix(n)).map { abs($0 - $1) }.max() ?? .nan
                    lines.append(String(format: "decoder_seek\t%@\tt=%.1f\tremuxed_error_ms=%.1f (peak %.3f)\tsource_error_ms=%.1f (peak %.3f)\tmax_abs_sample_difference=%.6f over %d samples",
                                        file, t, mr.errorMs, mr.peak, ms.errorMs, ms.peak, maxDiff, n))
                    #expect(abs(mr.errorMs) <= 500 && mr.peak >= 0.5, "\(file) t=\(t): remuxed content error \(mr.errorMs) ms")
                    #expect(abs(mr.errorMs - ms.errorMs) <= 1, "\(file) t=\(t): remux moved content by \(mr.errorMs - ms.errorMs) ms")
                }
                // Cold resume of the remuxed copy at 0.33 h and at the deepest point.
                for checkpointMs in [Self.depthsMs[0], durationMs - 400_700] {
                    let c = dir.appendingPathComponent("cold-\(UUID().uuidString.prefix(8)).\(ext)")
                    try FileManager.default.copyItem(at: remuxed, to: c)
                    defer { try? FileManager.default.removeItem(at: c) }
                    let x = try await Self.coldResume(c, durationMs: durationMs, checkpointMs: checkpointMs, master: master, label: "remuxed \(file)")
                    lines.append(String(format: "cold_resume_remuxed\t%@\tdepth_h=%.2f\tload_s=%.3f\tplay_to_audio_s=%.3f\tload_plus_play_s=%.3f\tcontent_error_ms=%.1f",
                                        file, Double(checkpointMs) / 3_600_000, x.load, x.playToAudio, x.total, x.contentErrorMs))
                    #expect(x.total <= 1.5, "remuxed \(file): cold resume \(x.total) s")
                }
                // A capture's excerpt export from the remuxed copy, 30 s ending 400.7 s before the end, cold.
                let e = dir.appendingPathComponent("export-\(UUID().uuidString.prefix(8)).\(ext)")
                try FileManager.default.copyItem(at: remuxed, to: e)
                defer { try? FileManager.default.removeItem(at: e) }
                let endMs = durationMs - 400_700
                let seg = SourceSegment(url: e, range: AudioRange(assetID: UUID(), startMs: endMs - 30_000, endMs: endMs))
                let x = try await ExcerptProbe.run([seg], masterStart: Double(endMs - 30_000) / 1000, masterEnd: Double(endMs) / 1000,
                                                   master: master, loopFrames: Fixtures.longLoopFrames)
                lines.append(String(format: "export_remuxed\t%@\tend_h=%.2f\texport_s=%.3f\tstart_error_ms=%.1f\tend_error_ms=%.1f",
                                    file, Double(endMs) / 3_600_000, x.exportSeconds, x.startErrorMs, x.endErrorMs))
                #expect(abs(x.startErrorMs) <= 500 && abs(x.endErrorMs) <= 500, "remuxed \(file): export errors \(x.startErrorMs)/\(x.endErrorMs) ms")
            }
        }
    }
}
