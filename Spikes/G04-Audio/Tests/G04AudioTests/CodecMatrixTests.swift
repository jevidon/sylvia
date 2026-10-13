import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit
extension RealAV {
    /// G0.4 codec/container matrix (plan 3.1, 10.1, 10.2, 19.2): playable, duration, chapters, seek accuracy (decoder
    /// and player, zero-tolerance seeks measured by cross-correlation against the PCM master), and excerpt export.
    /// Every fixture is an encode of master-600s.wav, so positions are checked against the master's samples, not
    /// against any timestamp the stack reports.
    @Suite("Codec matrix", .serialized)
    @MainActor
    struct CodecMatrixTests {
        /// What the matrix expects of a file's chapters. The expectation is pinned: a change in what AVFoundation
        /// reads fails the test, so ADR-0006's chapter caveats can only change together with this table.
        enum Chapters: String, Sendable {
            /// The file carries the 4-chapter table and AVFoundation reports it (titles, and starts within 50 ms).
            case exact
            /// The file carries the 4-chapter table, but AVFoundation (and the ID3 CHAP fallback) report none.
            case notRead = "not-read"
            /// The file carries no chapter metadata (the plain MP3 variants; CAF, which no tool here can write it
            /// into; the LibriVox section MP3, which has none).
            case noneInFile = "none-in-file"
        }

        struct Format: Sendable {
            var id: String
            var file: String
            var label: String
            var chapters: Chapters = .noneInFile
            /// The duration the file must report (ms, within 500 ms).
            var durationMs: Int64 = 600_000
        }

        static let formats: [Format] = [
            Format(id: "mp3-cbr", file: "fmt-mp3-cbr.mp3", label: "MP3 CBR 64 kb/s"),
            Format(id: "mp3-vbr-xing", file: "fmt-mp3-vbr-xing.mp3", label: "MP3 VBR, Xing/LAME header"),
            Format(id: "mp3-vbr-noxing", file: "fmt-mp3-vbr-noxing.mp3", label: "MP3 VBR, no Xing/VBRI header"),
            Format(id: "mp3-id3-chap", file: "fmt-mp3-chap.mp3", label: "MP3 CBR with ID3 CHAP chapters", chapters: .exact),
            // The real LibriVox section 01 MP3 as downloaded (MPEG-2 Layer III, 22.05 kHz mono, 64 kb/s CBR);
            // master-600s.wav is ffmpeg's decode of its first 600 s, so every check below applies unchanged.
            Format(id: "mp3-librivox-22k", file: "fmt-librivox-mp3-22k.mp3", label: "MP3 MPEG-2 Layer III 22.05 kHz mono (real LibriVox file)",
                   durationMs: 1_356_251),
            Format(id: "m4a-aac-lc", file: "fmt-m4a-aac-lc.m4a", label: "M4A AAC-LC 64 kb/s with chapters", chapters: .exact),
            Format(id: "m4a-he-aac-v1", file: "fmt-m4a-heaac-v1.m4a", label: "M4A HE-AAC v1 32 kb/s with chapters", chapters: .exact),
            Format(id: "m4a-he-aac-v2", file: "fmt-m4a-heaac-v2.m4a", label: "M4A HE-AAC v2 32 kb/s with chapters", chapters: .exact),
            Format(id: "m4a-alac", file: "fmt-m4a-alac.m4a", label: "M4A ALAC with chapters", chapters: .exact),
            Format(id: "flac", file: "fmt-flac.flac", label: "FLAC (native container), CHAPTERxxx Vorbis comments", chapters: .exact),
            Format(id: "mp4-flac", file: "fmt-mp4-flac.m4a", label: "FLAC in MP4 with chapters", chapters: .exact),
            Format(id: "ogg-opus", file: "fmt-opus.ogg", label: "Opus in Ogg (.ogg), CHAPTERxxx Vorbis comments", chapters: .exact),
            Format(id: "opus-ext", file: "fmt-opus.opus", label: "Opus in Ogg (.opus), CHAPTERxxx Vorbis comments", chapters: .exact),
            // Not playable (AVFoundation cannot open WebM), so its chapters are never checked.
            Format(id: "webm-opus", file: "fmt-webm-opus.webm", label: "Opus in WebM with Matroska chapters", chapters: .notRead),
            Format(id: "mp4-opus", file: "fmt-mp4-opus.m4a", label: "Opus in MP4 with chapters", chapters: .exact),
            Format(id: "caf-opus", file: "fmt-caf-opus.caf", label: "Opus in CAF"),
            Format(id: "wav", file: "fmt-wav.wav", label: "WAV PCM 16-bit, cue points with labels", chapters: .notRead),
        ]

        /// The provisional release list (ADR-0006): exactly the formats that pass every check below in the simulator.
        /// The test fails if a listed format stops passing or an unlisted one starts passing, so the list can only
        /// change together with the ADR. It stays provisional until the device run (device checklist step 1).
        static let provisionalReleaseList: Set<String> = [
            "mp3-cbr", "mp3-vbr-xing", "mp3-vbr-noxing", "mp3-id3-chap", "mp3-librivox-22k", "m4a-aac-lc", "m4a-he-aac-v1",
            "m4a-he-aac-v2", "m4a-alac", "flac", "mp4-flac", "ogg-opus", "opus-ext", "mp4-opus", "caf-opus", "wav",
        ]

        static let budgetMs = 500.0
        static let durationToleranceMs: Int64 = 500
        static let chapterToleranceMs: Int64 = 50
        static let decoderSeekPoints: [Double] = [1.75, 37.3, 151.7, 333.3, 471.05, 587.2]
        static let playerSeekPoints: [Double] = [37.3, 333.3, 587.2]
        /// Excerpts: preceding 30 s at an arbitrary point; clamped at the start; a 120-second extension.
        static let excerptSpans: [(start: Double, end: Double)] = [(221.37, 251.37), (0, 12.5), (455.55, 575.55)]
        static let minimumPeak: Float = 0.5

        @Test("Codec/container matrix (simulator or device; the environment is in the results header)", .timeLimit(.minutes(20)))
        func codecMatrix() async throws {
            let master = try Fixtures.master600()
            var rows: [String] = [
                "# G0.4 codec matrix. Environment: \(Results.environmentLabel()). Budget: \(Int(Self.budgetMs)) ms.",
                "# errors in ms; positive = audio starts/ends later in the source than intended; peak = normalized correlation",
                ["format", "file", "playable", "codec", "rate", "ch", "precise_ms", "estimated_ms", "chapters_expected", "chapters", "chapter_source",
                 "decoder_seek_max_abs_ms", "decoder_seek_min_peak", "player_start_offset_max_abs_ms", "player_steady_clock_error_max_abs_ms", "player_seek_to_audio_max_ms", "estimated_timing_player_start_offset_max_abs_ms",
                 "export_errors_ms(start/end;...)", "export_min_peak", "verdict", "reasons"].joined(separator: "\t"),
            ]
            var detail: [String] = ["format\tcheck\tpoint_s\terror_ms\tpeak\textra"]
            var passing: Set<String> = []

            for format in Self.formats {
                let url = try Fixtures.url(format.file)
                var reasons: [String] = []
                var cells: [String] = [format.id, format.file]

                // 1. Inspection
                let report: AssetReport?
                do { report = try await AssetInspector.inspect(url) } catch {
                    report = nil
                    reasons.append("inspect threw: \(error)")
                }
                let playable = report.map { $0.isPlayable && $0.audioTrackCount > 0 } ?? false
                cells += [playable ? "yes" : "no", report?.codec ?? "-", report?.sampleRate.map { "\(Int($0))" } ?? "-",
                          report?.channels.map(String.init) ?? "-", report?.preciseDurationMs.map(String.init) ?? "-",
                          report?.estimatedDurationMs.map(String.init) ?? "-", format.chapters.rawValue, "\(report?.chapters.count ?? 0)",
                          report?.chapterSource.rawValue ?? "-"]
                guard let report, playable else {
                    if report != nil { reasons.append("not playable") }
                    rows.append((cells + ["-", "-", "-", "-", "-", "-", "-", "-", "unsupported", oneLine(reasons.joined(separator: "; "))]).joined(separator: "\t"))
                    continue
                }
                if let d = report.preciseDurationMs {
                    if abs(d - format.durationMs) > Self.durationToleranceMs { reasons.append("duration \(d) ms, expected \(format.durationMs)") }
                } else { reasons.append("no duration") }
                switch format.chapters {
                case .exact:
                    if report.chapters.count != Fixtures.chapters600.count {
                        reasons.append("chapters \(report.chapters.count) of \(Fixtures.chapters600.count)")
                    } else {
                        for (got, want) in zip(report.chapters, Fixtures.chapters600) where
                            abs(got.startMs - want.startMs) > Self.chapterToleranceMs || got.title != want.title {
                            reasons.append("chapter \(want.title) got \(got.title)@\(got.startMs)")
                        }
                        // The last chapter runs to the end of the file (an indefinite end is closed at the duration).
                        if let last = report.chapters.last, abs(last.endMs - format.durationMs) > Self.durationToleranceMs {
                            reasons.append("last chapter ends at \(last.endMs) ms")
                        }
                    }
                case .notRead, .noneInFile:
                    if !report.chapters.isEmpty {
                        reasons.append("\(report.chapters.count) chapters reported where \(format.chapters.rawValue) was expected; update the expectation and ADR-0006")
                    }
                }
                detail.append("\(format.id)\tchapters\t-\t-\t-\texpected=\(format.chapters.rawValue) indefinite_ends_closed_at_duration=\(report.chapterEndsClosedAtDuration) reported=\(report.chapters.map { "\($0.title)@\($0.startMs)-\($0.endMs)" }.joined(separator: "; "))")

                // 2. Decoder seek accuracy (AVAssetReader timeRange: the excerpt path)
                var decoderMax = 0.0
                var decoderMinPeak: Float = 1
                for t in Self.decoderSeekPoints {
                    do {
                        let pcm = try await PCMDecoder.decode(url: url, start: t, duration: 4)
                        guard let m = try TimingVerifier.measure(audio: pcm.samples, rate: pcm.sampleRate, intendedStart: t, master: master) else {
                            reasons.append("decoder seek \(t)s unmeasurable"); continue
                        }
                        decoderMax = max(decoderMax, abs(m.errorMs))
                        decoderMinPeak = min(decoderMinPeak, m.peak)
                        detail.append("\(format.id)\tdecoder_seek\t\(t)\t\(fmt(m.errorMs))\t\(fmt(m.peak))\treported_start=\(fmt(pcm.reportedStart))")
                    } catch { reasons.append("decoder seek \(t)s: \(error)") }
                }
                if decoderMax > Self.budgetMs { reasons.append("decoder seek error \(fmt(decoderMax)) ms") }
                if decoderMinPeak < Self.minimumPeak { reasons.append("decoder content mismatch (peak \(fmt(decoderMinPeak)))") }
                cells += [fmt(decoderMax), fmt(decoderMinPeak)]

                // 3. Player seek accuracy (AVPlayer, zero tolerance; rendered audio via tap)
                var firstMax = 0.0, steadyMax = 0.0
                var latencies: [Double] = []
                let probe = PlayerProbe(url: url)
                if try await probe.prepare() {
                    for t in Self.playerSeekPoints {
                        guard let r = try await probe.seekAndListen(to: t) else {
                            reasons.append("player seek \(t)s unmeasurable [\(probe.lastDiagnostic)]"); continue
                        }
                        let m = try PlayerProbe.measure(r, reference: master)
                        if let e = m.steadyErrorMs, let p = m.steadyPeak, p >= Self.minimumPeak, let o = m.startOffsetMs {
                            steadyMax = max(steadyMax, abs(e))
                            firstMax = max(firstMax, abs(o))
                        } else {
                            reasons.append("player steady run at \(t)s unmeasurable (peak \(m.steadyPeak.map { fmt($0) } ?? "-"))")
                        }
                        if let l = r.startLatency { latencies.append(l) } else { reasons.append("no audio at \(t)s within 15 s of play") }
                        detail.append("\(format.id)\tplayer_seek\t\(t)\tstart_offset=\(m.startOffsetMs.map { fmt($0) } ?? "-") steady=\(m.steadyErrorMs.map { fmt($0) } ?? "-")\tsteady_peak=\(m.steadyPeak.map { fmt($0) } ?? "-")\tfirst_buffer_error=\(m.firstBufferErrorMs.map { fmt($0) } ?? "-") (peak \(m.firstBufferPeak.map { fmt($0) } ?? "-")) steady_reported=\(fmt(r.steadyReportedStart)) current_after_seek=\(fmt(r.currentTimeAfterSeek)) finished=\(r.seekFinished) preroll_buffers_before_target=\(r.precedingRuns) \(r.diagnostic)")
                    }
                } else {
                    reasons.append("AVPlayerItem not ready: \(String(describing: probe.item.error))")
                }
                probe.stop()
                if max(firstMax, steadyMax) > Self.budgetMs { reasons.append("player seek error \(fmt(max(firstMax, steadyMax))) ms") }
                cells += [fmt(firstMax), fmt(steadyMax), latencies.max().map { fmt($0 * 1000) } ?? "-"]

                // 3b. The same player seeks without AVURLAssetPreferPreciseDurationAndTimingKey (information for the
                //     precise-versus-estimated decision in ADR-0006; not a pass criterion).
                var estimatedMax = 0.0
                let estimatedProbe = PlayerProbe(url: url, precise: false)
                if try await estimatedProbe.prepare() {
                    for t in Self.playerSeekPoints {
                        guard let r = try await estimatedProbe.seekAndListen(to: t),
                              let o = try PlayerProbe.measure(r, reference: master).startOffsetMs else { estimatedMax = .infinity; continue }
                        estimatedMax = max(estimatedMax, abs(o))
                        detail.append("\(format.id)\tplayer_seek_estimated_timing\t\(t)\tstart_offset=\(fmt(o))\t-\t\(r.diagnostic.prefix(60))")
                    }
                }
                estimatedProbe.stop()
                cells.append(estimatedMax.isFinite ? fmt(estimatedMax) : "unmeasurable")

                // 4. Excerpt export (AAC .m4a), measured at both ends
                var exportCells: [String] = []
                var exportMinPeak: Float = 1
                let asset = UUID()
                for span in Self.excerptSpans {
                    do {
                        let seg = SourceSegment(url: url, range: AudioRange(assetID: asset, startMs: Int64((span.start * 1000).rounded()), endMs: Int64((span.end * 1000).rounded())))
                        let r = try await ExcerptProbe.run([seg], masterStart: span.start, masterEnd: span.end, master: master)
                        exportCells.append("\(fmt(r.startErrorMs))/\(fmt(r.endErrorMs))")
                        exportMinPeak = min(exportMinPeak, r.startPeak, r.endPeak)
                        if abs(r.startErrorMs) > Self.budgetMs || abs(r.endErrorMs) > Self.budgetMs {
                            reasons.append("export \(span.start)-\(span.end) error \(fmt(r.startErrorMs))/\(fmt(r.endErrorMs)) ms")
                        }
                        detail.append("\(format.id)\texport\t\(span.start)-\(span.end)\t\(fmt(r.startErrorMs))/\(fmt(r.endErrorMs))\t\(fmt(min(r.startPeak, r.endPeak)))\tlength_error_ms=\(fmt(r.lengthErrorMs)) claimed_start_offset_ms=\(fmt(r.claimedStartOffsetMs)) output_duration_ms=\(r.exported.outputDurationMs.map(String.init) ?? "-") bytes=\(r.exported.byteCount)")
                    } catch {
                        exportCells.append("fail")
                        reasons.append("export \(span.start)-\(span.end): \(error)")
                    }
                }
                if exportMinPeak < Self.minimumPeak { reasons.append("export content mismatch (peak \(fmt(exportMinPeak)))") }
                cells += [exportCells.joined(separator: ";"), fmt(exportMinPeak)]

                let pass = reasons.isEmpty
                if pass { passing.insert(format.id) }
                rows.append((cells + [pass ? "pass" : "fail", oneLine(reasons.joined(separator: "; "))]).joined(separator: "\t"))
            }

            Results.write("codec-matrix.tsv", rows)
            Results.write("codec-matrix-detail.tsv", detail)
            for id in Self.provisionalReleaseList.subtracting(passing).sorted() {
                Issue.record("listed format \(id) no longer passes; see codec-matrix.tsv")
            }
            for id in passing.subtracting(Self.provisionalReleaseList).sorted() {
                Issue.record("format \(id) passes but is not on the provisional release list; update ADR-0006 and this list")
            }
        }
    }
}

func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
/// Collapses whitespace runs (error descriptions contain newlines) so a TSV row stays on one line.
func oneLine(_ s: String) -> String { s.split(whereSeparator: { $0.isNewline || $0 == "\t" }).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ") }
func fmt(_ x: Float) -> String { String(format: "%.3f", x) }
