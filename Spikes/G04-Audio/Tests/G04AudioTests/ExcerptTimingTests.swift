import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// Measures an exported excerpt file against the master at its head, at every seam between ranges and at its tail.
enum ExcerptMeasure {
    struct Piece {
        /// Where this range's audio starts in master time (seconds).
        var masterStart: Double
        var duration: Double
    }

    struct Result {
        var headErrorMs: Double
        var seamErrorsMs: [Double]
        var tailErrorMs: Double
        var minPeak: Float
        var lengthErrorMs: Double
        var all: [Double] { [headErrorMs] + seamErrorsMs + [tailErrorMs] }
    }

    struct Unmeasurable: Error, CustomStringConvertible { var description: String }

    /// `loopFrames` folds positions of the looped 10-hour fixtures back into master-long.
    static func measure(_ url: URL, pieces: [Piece], master: any PCMSource, loopFrames: Int? = nil) async throws -> Result {
        let decoded = try await PCMDecoder.decode(url: url, start: 0, duration: nil)
        let x = decoded.samples, rate = decoded.sampleRate
        var peaks: [Float] = []
        func at(_ offsetSeconds: Double, intended: Double, length: Double, label: String) throws -> Double {
            let s = max(0, Int((offsetSeconds * rate).rounded()))
            let e = min(x.count, s + Int(length * rate))
            guard e - s > Int(1.6 * rate) else { throw Unmeasurable(description: "\(label): window too short") }
            guard let m = try TimingVerifier.measure(audio: Array(x[s..<e]), rate: rate, intendedStart: intended, master: master,
                                                     loopFrames: loopFrames, scanSeconds: max(0, length - 1.6)) else {
                throw Unmeasurable(description: "\(label): no match")
            }
            peaks.append(m.peak)
            return m.errorMs
        }
        let head = try at(0, intended: pieces[0].masterStart, length: min(6, pieces[0].duration), label: "head")
        var seams: [Double] = []
        var offset = 0.0
        for (i, p) in pieces.enumerated() where i > 0 {
            offset += pieces[i - 1].duration
            seams.append(try at(offset, intended: p.masterStart, length: min(6, p.duration), label: "seam \(i)"))
        }
        let total = pieces.reduce(0) { $0 + $1.duration }
        let last = pieces[pieces.count - 1]
        let tailLength = min(4, last.duration)
        // The tail window ends where the output ends; its intended start is the last range's end minus the window.
        let outputSeconds = Double(x.count) / rate
        let tailStart = outputSeconds - tailLength
        let tailMeasured = try at(tailStart, intended: last.masterStart + last.duration - tailLength, length: tailLength, label: "tail")
        // tailMeasured is the content error at the window start; the end error is the same shift (equal lengths).
        return Result(headErrorMs: head, seamErrorsMs: seams, tailErrorMs: tailMeasured, minPeak: peaks.min() ?? 0,
                      lengthErrorMs: (outputSeconds - total) * 1000)
    }
}

extension RealAV {
    /// Excerpt export timing (plan 10.2, 19.2; T21): the preceding 30 s at arbitrary points, clamped at both
    /// bounds, trimmed and extended up to 120 s, across file boundaries and across formats, exported through the
    /// AAC .m4a path. Every exported file is decoded and cross-correlated with the PCM master at its head, at each
    /// seam and at its tail; the distribution per source format is reported against the 500 ms budget.
    @Suite("Excerpt timing distribution", .serialized)
    @MainActor
    struct ExcerptTimingTests {
        static let budgetMs = 500.0

        struct Span: CustomStringConvertible {
            var start: Double
            var end: Double
            var kind: String
            var description: String { "\(kind) \(String(format: "%.2f", start))-\(String(format: "%.2f", end))" }
        }

        /// 14 spans per format (seeded, the same for every format): eight "preceding 30 s" captures at arbitrary
        /// points, one clamped at the start, one clamped at the end, three trimmed or extended to random lengths
        /// (1-120 s) and one full 120 s extension.
        static func spans() -> [Span] {
            var rng = SeededRNG(seed: 604)
            func uniform(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * Double(rng.next() % 1_000_000) / 1_000_000 }
            let durationMs: Int64 = 600_000
            var result: [Span] = []
            for _ in 0..<8 {
                let p = Int64(uniform(31, 599) * 1000)
                let r = CaptureRange.preceding(globalMs: p, durationMs: durationMs)
                result.append(Span(start: Double(r.start) / 1000, end: Double(r.end) / 1000, kind: "preceding30"))
            }
            let early = CaptureRange.preceding(globalMs: Int64(uniform(2, 29) * 1000), durationMs: durationMs)
            result.append(Span(start: Double(early.start) / 1000, end: Double(early.end) / 1000, kind: "clamped-start"))
            let late = CaptureRange.preceding(globalMs: 640_000, durationMs: durationMs)
            result.append(Span(start: Double(late.start) / 1000, end: Double(late.end) / 1000, kind: "clamped-end"))
            for _ in 0..<3 {
                let length = uniform(1, 120)
                let end = uniform(length + 0.5, 599.5)
                result.append(Span(start: end - length, end: end, kind: "trim-extend"))
            }
            result.append(Span(start: 312.345, end: 432.345, kind: "extend120"))
            return result.map { s in
                // Whole milliseconds, as the capture record stores them.
                Span(start: (s.start * 1000).rounded() / 1000, end: (s.end * 1000).rounded() / 1000, kind: s.kind)
            }
        }

        @Test("Single-file excerpts: error distribution per format", .timeLimit(.minutes(20)))
        func singleFileDistribution() async throws {
            let master = try Fixtures.master600()
            let spans = Self.spans()
            for s in spans { try CaptureRange.validate(startMs: Int64(s.start * 1000), endMs: Int64(s.end * 1000), durationMs: 600_000) }
            var summary = [
                "# Excerpt export timing per source format (AAC .m4a output). Environment: \(Results.environmentLabel())",
                "# \(spans.count) excerpts per format; errors = true content position minus intended, ms (positive = later); budget \(Int(Self.budgetMs)) ms",
                "# claimed = the actual range the exporter stores (decoder timestamps) minus the true start",
                "# mp3-librivox-22k is the real 1,356 s LibriVox file: its spans are the same (all inside the 600 s master), so its clamped-end span is 570-600 s, not the end of that file",
                "format\tn\tstart_p50_abs\tstart_p95_abs\tstart_max_abs\tend_p50_abs\tend_p95_abs\tend_max_abs\tclaimed_vs_true_max_abs\tmin_peak\twithin_budget",
            ]
            var detail = ["format\tspan\tstart_err_ms\tend_err_ms\tclaimed_vs_true_ms\tlength_err_ms\tpeak\toutput_duration_ms\tsource_format(stored)"]
            defer {
                Results.write("excerpt-timing-single-file.tsv", summary)
                Results.write("excerpt-timing-single-file-detail.tsv", detail)
            }
            for format in CodecMatrixTests.formats where CodecMatrixTests.provisionalReleaseList.contains(format.id) {
                let url = try Fixtures.url(format.file)
                var starts: [Double] = [], ends: [Double] = [], claims: [Double] = []
                var minPeak: Float = 1
                for (index, span) in spans.enumerated() {
                    let seg = SourceSegment(url: url, range: AudioRange(assetID: UUID(), startMs: Int64(span.start * 1000), endMs: Int64(span.end * 1000)))
                    // The first preceding-30 s excerpt and the 120 s extension of each format are kept for the
                    // decoder-portability check (ffmpeg; `PortabilityTests`).
                    let keep = index == 0 || span.kind == "extend120" ? "\(format.id)-\(span.kind)" : nil
                    let r = try await ExcerptProbe.run([seg], masterStart: span.start, masterEnd: span.end, master: master, keep: keep)
                    let claimedStart = Double(r.exported.actualRanges[0].startMs) / 1000
                    let claimVsTrue = (claimedStart - (span.start + r.startErrorMs / 1000)) * 1000
                    starts.append(abs(r.startErrorMs)); ends.append(abs(r.endErrorMs)); claims.append(abs(claimVsTrue))
                    minPeak = min(minPeak, r.startPeak, r.endPeak)
                    detail.append("\(format.id)\t\(span)\t\(fmt(r.startErrorMs))\t\(fmt(r.endErrorMs))\t\(fmt(claimVsTrue))\t\(fmt(r.lengthErrorMs))\t\(fmt(min(r.startPeak, r.endPeak)))\t\(r.exported.outputDurationMs.map(String.init) ?? "-")\t\(r.exported.sourceFormats.joined(separator: ","))")
                    #expect(r.exported.sourceFormats.count == 1 && r.exported.sourceFormats[0] != "unknown", "\(format.id): source format \(r.exported.sourceFormats)")
                    #expect(abs(r.startErrorMs) <= Self.budgetMs, "\(format.id) \(span) start \(r.startErrorMs) ms")
                    #expect(abs(r.endErrorMs) <= Self.budgetMs, "\(format.id) \(span) end \(r.endErrorMs) ms")
                    #expect(min(r.startPeak, r.endPeak) >= 0.5, "\(format.id) \(span) content mismatch")
                }
                let ok = (starts + ends).allSatisfy { $0 <= Self.budgetMs }
                summary.append([format.id, "\(spans.count)",
                                fmt(Results.percentile(starts, 50)), fmt(Results.percentile(starts, 95)), fmt(starts.max() ?? .nan),
                                fmt(Results.percentile(ends, 50)), fmt(Results.percentile(ends, 95)), fmt(ends.max() ?? .nan),
                                fmt(claims.max() ?? .nan), fmt(minPeak), ok ? "yes" : "no"].joined(separator: "\t"))
            }
        }

        /// Cross-file excerpts through the real capture transaction: CaptureService writes the anchor (several
        /// ordered file-local ranges), the AAC exporter preserves the excerpt, and the stored record carries the
        /// actual exported ranges. The excerpt is checked at its head, at the seam and at its tail.
        @Test("Cross-file excerpts on the multi-file book (T21)", .timeLimit(.minutes(10)))
        func crossFile() async throws {
            let edition = try await RealEdition()
            let master = try Fixtures.masterLong()
            let store = try temporaryStore()
            let captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: edition.resolver())
            var lines = ["# Cross-file excerpts (multi-file MP3 book; T21). Environment: \(Results.environmentLabel())",
                         "# requests are global ms of the edition timeline (sum of AVFoundation's precise member durations)",
                         "# errors = true content position (cross-correlation with master-long at the member's true slice start + file-local ms) minus intended (ms)"]
            for (i, m) in edition.timeline.members.enumerated() {
                // AVFoundation's MP3 durations include the encoder delay and padding that LAME's gapless header
                // describes; the excess is silence the player and the exporter both play at each member boundary.
                let excess = m.durationMs - Int64((Fixtures.multi[i].duration * 1000).rounded())
                lines.append("# member \(i + 1) \(m.fileName): reported \(m.durationMs) ms, true content \(Int64((Fixtures.multi[i].duration * 1000).rounded())) ms, excess \(excess) ms")
                #expect(abs(excess) <= 100, "\(m.fileName) duration excess \(excess) ms")
            }
            lines.append("request\tranges(stored)\tactual_ranges(stored)\thead_err\tseam_errs\ttail_err\tlength_err\tmin_peak\tstatus")
            defer { Results.write("excerpt-timing-cross-file.tsv", lines) }
            let boundaries = Array(edition.timeline.starts.dropFirst())
            var requests: [(start: Int64, end: Int64, label: String)] = []
            var all: [Double] = []
            for b in boundaries {
                // Default capture with the boundary inside the preceding 30 s, a capture 0.1 s after the boundary
                // (a 0.1 s second range), and a 120 s extension across the boundary.
                requests.append((b - 15_000, b + 15_000, "preceding30 at boundary+15s"))
                requests.append((b - 29_900, b + 100, "preceding30 at boundary+0.1s"))
                requests.append((b - 100_000, b + 20_000, "extend120"))
            }
            for req in requests {
                // Capture at the end point (default 30 s), then set the requested range with the numeric controls.
                var record = try captures.captureAudio(timeline: edition.timeline, atGlobalMs: req.end, note: "cross-file",
                                                             idempotencyKey: UUID().uuidString)
                if req.end - req.start != CaptureRange.defaultLengthMs {
                    record = try await captures.setRange(record.id, timeline: edition.timeline, globalStartMs: req.start, globalEndMs: req.end)
                }
                #expect(record.ranges.count == 2, "\(req.label): \(record.ranges)")
                #expect(try edition.timeline.globalSpan(of: record.ranges).map { [$0.startMs, $0.endMs] } == [req.start, req.end])
                let done = try await captures.preserveExcerpt(record.id)
                guard case let .saved(exported) = done.excerpt else {
                    Issue.record("\(req.label): excerpt not preserved: \(done.excerpt)")
                    lines.append("\(req.start)-\(req.end)\t-\t-\t-\t-\t-\t-\t-\t\(done.excerpt)")
                    continue
                }
                #expect(done.statusKey == .audioExcerptSaved)
                // The stored record (re-read from disk) carries the actual exported timing.
                let reread = try #require(try FileCaptureStore(directory: store.directory).record(record.id))
                #expect(reread == done)
                // Where each file-local range really sits in master-long: the member's true slice start (from the
                // generate script) plus the file-local offset. The global timeline is not used here, because it is
                // built from the durations AVFoundation reports, which include each MP3's encoder delay and padding.
                let pieces = try done.ranges.map { r in
                    let i = try #require(edition.ids.firstIndex(of: r.assetID))
                    return ExcerptMeasure.Piece(masterStart: Fixtures.multi[i].start + Double(r.startMs) / 1000,
                                                duration: Double(r.durationMs) / 1000)
                }
                // A 0.1 s piece is too short to correlate on its own; it is still covered by the tail window.
                let measurable = pieces.filter { $0.duration >= 2 }
                let m: ExcerptMeasure.Result
                if measurable.count == pieces.count {
                    m = try await ExcerptMeasure.measure(store.excerptURL(for: record.id), pieces: pieces, master: master)
                } else {
                    // Measure head and tail with the short piece folded into the long one (contiguous in master time).
                    let merged = ExcerptMeasure.Piece(masterStart: pieces[0].masterStart, duration: pieces.reduce(0) { $0 + $1.duration })
                    m = try await ExcerptMeasure.measure(store.excerptURL(for: record.id), pieces: [merged], master: master)
                }
                all += m.all.map(abs)
                let actual = exported.actualRanges.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ",")
                let stored = done.ranges.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ",")
                lines.append("\(req.start)-\(req.end) \(req.label)\t\(stored)\t\(actual)\t\(fmt(m.headErrorMs))\t\(m.seamErrorsMs.map { fmt($0) }.joined(separator: ","))\t\(fmt(m.tailErrorMs))\t\(fmt(m.lengthErrorMs))\t\(fmt(m.minPeak))\t\(SpikePhrases.phrase(done.statusKey))")
                for e in m.all { #expect(abs(e) <= Self.budgetMs, "\(req.label) \(req.start)-\(req.end): \(e) ms") }
                #expect(m.minPeak >= 0.5)
            }
            lines.append("# n=\(all.count) measurements; p50_abs=\(fmt(Results.percentile(all, 50))) p95_abs=\(fmt(Results.percentile(all, 95))) max_abs=\(fmt(all.max() ?? .nan))")
        }

        /// T23 with real files: a retained excerpt stays playable and correct after the full source is removed; a
        /// capture whose excerpt was still pending when the source went is guarded first and then fails honestly
        /// ("Excerpt not preserved · Retry"), keeping its anchor and note.
        @Test("Removing the source after a successful and a pending excerpt (T23)", .timeLimit(.minutes(5)))
        func sourceRemovalAfterSuccessfulAndPendingExcerpts() async throws {
            let master = try Fixtures.master600()
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-t23-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            // The library's managed copy of the audiobook (plan I-08: imports copy into Sylvia storage).
            let source = dir.appendingPathComponent("book.m4a")
            try FileManager.default.copyItem(at: try Fixtures.url("fmt-m4a-aac-lc.m4a"), to: source)
            let asset = UUID()
            let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: asset, fileName: "book.m4a", durationMs: 600_000)])
            let store = try FileCaptureStore(directory: dir.appendingPathComponent("knowledge"))
            let resolver: CaptureService.SourceResolver = { id in
                id == asset && FileManager.default.fileExists(atPath: source.path) ? source : nil
            }
            let captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: resolver)

            let kept = try captures.captureAudio(timeline: timeline, atGlobalMs: 300_000, note: "kept", idempotencyKey: "t23-a")
            let saved = try await captures.preserveExcerpt(kept.id)
            #expect(saved.statusKey == .audioExcerptSaved)
            let pending = try captures.captureAudio(timeline: timeline, atGlobalMs: 450_000, note: "pending", idempotencyKey: "t23-b")
            // Before removal: the pending capture makes removal an explicit choice.
            let impact = try await captures.sourceRemovalImpact(assetID: asset)
            #expect(impact.requiresExplicitChoice)
            #expect(impact.unpreservedCaptures == [pending.id] && impact.preservedCaptures == [kept.id])

            // The user removes the download anyway.
            try FileManager.default.removeItem(at: source)
            let afterExport = try await captures.preserveExcerpt(pending.id)
            #expect(afterExport.statusKey == .audioExcerptNotPreserved)
            #expect(afterExport.note == "pending" && afterExport.ranges == pending.ranges)

            // The retained excerpt still decodes, from the right place in the book.
            let m = try await ExcerptMeasure.measure(store.excerptURL(for: kept.id), pieces: [.init(masterStart: 270, duration: 30)], master: master)
            Results.write("t23-source-removal.txt", [
                "# T23: source removed after a successful and a pending excerpt. Environment: \(Results.environmentLabel())",
                "retained excerpt after source removal: head_err_ms=\(fmt(m.headErrorMs)) tail_err_ms=\(fmt(m.tailErrorMs)) length_err_ms=\(fmt(m.lengthErrorMs)) min_peak=\(fmt(m.minPeak)) status=\(SpikePhrases.phrase(saved.statusKey))",
                "pending capture after source removal: status=\(SpikePhrases.phrase(afterExport.statusKey)) note_kept=\(afterExport.note == "pending") ranges_kept=\(afterExport.ranges == pending.ranges) excerpt=\(afterExport.excerpt)",
                "removal impact before removal: unpreserved=\(impact.unpreservedCaptures.count) preserved=\(impact.preservedCaptures.count) requires_explicit_choice=\(impact.requiresExplicitChoice)",
            ])
            for e in m.all { #expect(abs(e) <= Self.budgetMs) }
            #expect(m.minPeak >= 0.5)
        }

        /// One excerpt whose three ranges come from three files in different formats (an edition may mix them):
        /// MP3, AAC and FLAC encodes of the same master, consecutive in master time.
        @Test("Three ranges from three formats in one excerpt", .timeLimit(.minutes(5)))
        func threeRangesMixedFormats() async throws {
            let master = try Fixtures.master600()
            let plan: [(file: String, start: Double, end: Double)] = [
                ("fmt-mp3-cbr.mp3", 200.0, 214.5), ("fmt-m4a-aac-lc.m4a", 214.5, 241.25), ("fmt-flac.flac", 241.25, 258.0),
            ]
            let segments = try plan.map {
                SourceSegment(url: try Fixtures.url($0.file), range: AudioRange(assetID: UUID(), startMs: Int64($0.start * 1000), endMs: Int64($0.end * 1000)))
            }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("g04-three-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: out) }
            let exported = try await AACExcerptExporter().export(segments, to: out)
            #expect(exported.requestedRanges.count == 3 && exported.actualRanges.count == 3)
            // The record keeps each range's source format, so a per-codec timing correction can be applied later.
            #expect(exported.sourceFormats == [".mp3/44100/1", "aac /44100/1", "flac/44100/1"])
            let m = try await ExcerptMeasure.measure(out, pieces: plan.map { .init(masterStart: $0.start, duration: $0.end - $0.start) }, master: master)
            Results.write("excerpt-timing-three-formats.txt", [
                "# One excerpt, three ranges: MP3 200-214.5 s, AAC 214.5-241.25 s, FLAC 241.25-258 s. Environment: \(Results.environmentLabel())",
                "head_err_ms=\(fmt(m.headErrorMs)) seam_errs_ms=\(m.seamErrorsMs.map { fmt($0) }.joined(separator: ",")) tail_err_ms=\(fmt(m.tailErrorMs)) length_err_ms=\(fmt(m.lengthErrorMs)) min_peak=\(fmt(m.minPeak))",
                "actual_ranges=\(exported.actualRanges.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ",")) source_formats=\(exported.sourceFormats.joined(separator: ",")) output_duration_ms=\(exported.outputDurationMs.map(String.init) ?? "-")",
            ])
            for e in m.all { #expect(abs(e) <= Self.budgetMs) }
            #expect(m.seamErrorsMs.count == 2)
            #expect(m.minPeak >= 0.5)
        }
    }
}
