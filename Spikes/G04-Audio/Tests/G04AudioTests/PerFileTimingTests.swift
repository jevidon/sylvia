import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// The MPEG frames of an MP3 file after its leading ID3v2 tags (offset, length, bit rate), for building variants.
enum MP3Frames {
    static func list(_ data: Data) -> [(offset: Int, length: Int, kbps: Int)] {
        data.withUnsafeBytes { b in
            var pos = 0
            while pos + 10 <= b.count, b[pos] == 0x49, b[pos + 1] == 0x44, b[pos + 2] == 0x33 {
                let size = Int(b[pos + 6]) << 21 | Int(b[pos + 7]) << 14 | Int(b[pos + 8]) << 7 | Int(b[pos + 9])
                pos += 10 + size + (b[pos + 5] & 0x10 != 0 ? 10 : 0)
            }
            var frames: [(offset: Int, length: Int, kbps: Int)] = []
            while pos + 4 <= b.count {
                let h = UInt32(b[pos]) << 24 | UInt32(b[pos + 1]) << 16 | UInt32(b[pos + 2]) << 8 | UInt32(b[pos + 3])
                guard let header = MP3FrameScanner.Header(h), let length = header.length, let kbps = header.bitRateKbps,
                      pos + length <= b.count else { break }
                frames.append((pos, length, kbps))
                pos += length
            }
            return frames
        }
    }
}

/// The metadata blocks of a native FLAC file ("STREAMINFO", "SEEKTABLE(n points)", ...), to show which files carry a
/// seek table (review R4-01: the codec matrix's 10-minute FLAC has none; the long files have one every 10 s).
enum FLACMetadata {
    static func blocks(_ url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: 4 << 20) ?? Data()
        let b = [UInt8](head)
        guard b.count >= 4, b[0] == 0x66, b[1] == 0x4C, b[2] == 0x61, b[3] == 0x43 else { return ["not a native FLAC file"] }
        let names = ["STREAMINFO", "PADDING", "APPLICATION", "SEEKTABLE", "VORBIS_COMMENT", "CUESHEET", "PICTURE"]
        var pos = 4
        var out: [String] = []
        while pos + 4 <= b.count {
            let last = b[pos] & 0x80 != 0
            let type = Int(b[pos] & 0x7F)
            let length = Int(b[pos + 1]) << 16 | Int(b[pos + 2]) << 8 | Int(b[pos + 3])
            let name = type < names.count ? names[type] : "TYPE\(type)"
            out.append(type == 3 ? "SEEKTABLE(\(length / 18) points)" : name)
            pos += 4 + length
            if last { return out }
        }
        out.append("(metadata continues past the first 4 MB)")
        return out
    }
}

extension RealAV {
    /// The per-file timing mode (ADR-0006 decision 2; review R4-01). Precise timing is exact everywhere but slow to open
    /// some containers and slow to seek deep into an MP3; estimated timing is fast everywhere and exact only where
    /// AVFoundation can compute a position from the bit rate. These tests check the import's proof of a constant bit
    /// rate on every MP3 fixture and on variants made from them, then measure estimated timing in the proved files on
    /// every path the product opens a file (decoder, cold resume in `BudgetTests`, the capture export, the pending
    /// preview, cross-file captures), against the PCM masters and against precise timing; and record where estimated
    /// timing is wrong (VBR MP3, native FLAC with and without a seek table), which is why the import never chooses it
    /// there.
    @Suite("Per-file timing mode: constant-bit-rate MP3 proved at import, opened with estimated timing (R4-01)", .serialized)
    @MainActor
    struct PerFileTimingTests {
        static let cbrFixtures = ["fmt-mp3-cbr.mp3", "fmt-mp3-chap.mp3", "fmt-librivox-mp3-22k.mp3", "multi/Part 2.mp3", "multi/Part 1.mp3",
                                  "multi/Part 3.mp3", "multi/Part 10.mp3", "long-mp3-cbr-10h.mp3"]
        static let vbrFixtures = ["fmt-mp3-vbr-xing.mp3", "fmt-mp3-vbr-noxing.mp3", "long-mp3-vbr-10h.mp3", "long-formats/long-mp3-vbr-noxing-10h.mp3"]
        static let otherFormats = ["fmt-m4a-aac-lc.m4a", "fmt-flac.flac", "fmt-opus.ogg", "fmt-wav.wav"]

        static func scratch(_ name: String) throws -> URL {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-\(name)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }

        /// A fresh copy of a fixture (a new file to AVFoundation, as after a relaunch).
        static func freshCopy(_ relative: String, in dir: URL) throws -> URL {
            let source = try Fixtures.url(relative)
            let copy = dir.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(source.lastPathComponent)")
            try FileManager.default.copyItem(at: source, to: copy)
            return copy
        }

        static func bitRates(_ scan: MP3FrameScanner.Scan?) -> String {
            guard let scan else { return "-" }
            return scan.bitRateList.map { "\($0):\(scan.bitRates[$0] ?? 0)" }.joined(separator: ",")
        }

        @Test("Import: which MP3 files the frame scan proves constant bit rate, and the timing chosen", .timeLimit(.minutes(10)))
        func detection() async throws {
            var lines = ["# The import's per-file timing decision (ADR-0006 decision 2; review R4-01). Environment: \(Results.environmentLabel())",
                         "# timing: estimatedCBR only for an MP3 whose every frame has one bit rate, sample rate, version and channel count, contiguous from the",
                         "# first frame to the end of the audio (or an APEv2/ID3v1 tag), with an Info tag whose frame count matches or no tag, and whose scanned",
                         "# audio duration agrees with AVFoundation's precise duration within three frames; precise otherwise. scan_s = the frame walk alone;",
                         "# inspect_s = the whole import inspection. Variants are made from the fixtures in a scratch folder.",
                         "file\tcodec\ttiming\treason\tframes\tbit_rates_kbps(frames)\ttag\ttag_frames\ttrailing_tags\tbytes\tscan_s\tinspect_s\tprecise_ms\testimated_ms\tscanned_audio_ms"]
            defer { Results.write("mp3-cbr-detection.tsv", lines) }
            let dir = try Self.scratch("detect")
            defer { try? FileManager.default.removeItem(at: dir) }

            // Variants of the 10-minute CBR encode (and of the VBR one).
            let cbr = try Data(contentsOf: try Fixtures.url("fmt-mp3-cbr.mp3"))
            let frames = MP3Frames.list(cbr)
            #expect(frames.count == 22_971)
            let vbr = try Data(contentsOf: try Fixtures.url("fmt-mp3-vbr-xing.mp3"))
            let vbrFrames = MP3Frames.list(vbr)
            let odd = try #require(vbrFrames.indices.first { $0 >= 10_000 && vbrFrames[$0].kbps != 64 })
            var noTag = cbr
            noTag.removeSubrange(frames[0].offset..<frames[0].offset + frames[0].length)
            var spliced = cbr
            spliced.replaceSubrange(frames[odd].offset..<frames[odd].offset + frames[odd].length,
                                    with: vbr[vbrFrames[odd].offset..<vbrFrames[odd].offset + vbrFrames[odd].length])
            let id3v1 = Data("TAG".utf8) + Data(repeating: 0x20, count: 125)
            let part2 = try Data(contentsOf: try Fixtures.url("multi/Part 2.mp3"))
            let variants: [(name: String, data: Data, timing: AssetTiming, reason: String)] = [
                ("cbr-no-info-tag.mp3", noTag, .estimatedCBR, "no tag"),
                ("cbr-plus-id3v1.mp3", cbr + id3v1, .estimatedCBR, "Info tag"),
                ("cbr-one-\(vbrFrames[odd].kbps)k-frame-at-\(odd).mp3", spliced, .precise, "variable bit rate: 2 bit rates"),
                ("cbr-plus-100-zero-bytes.mp3", cbr + Data(count: 100), .precise, "no frame header at byte"),
                ("cbr-then-part2-concatenated.mp3", cbr + part2, .precise, "an ID3 tag inside the audio"),
            ]
            var files: [(label: String, url: URL, timing: AssetTiming, reason: String?)] = []
            for f in Self.cbrFixtures { files.append((f, try Fixtures.url(f), .estimatedCBR, "Info tag")) }
            for f in Self.vbrFixtures { files.append((f, try Fixtures.url(f), .precise, "variable bit rate")) }
            for v in variants {
                let url = dir.appendingPathComponent(v.name)
                try v.data.write(to: url)
                files.append(("variant: \(v.name)", url, v.timing, v.reason))
            }
            for f in Self.otherFormats { files.append((f, try Fixtures.url(f), .precise, "not MP3")) }

            for f in files {
                let report = try await AssetInspector.inspect(f.url)
                let d = report.timingDecision
                let scan = d.scan
                let bytes = (try FileManager.default.attributesOfItem(atPath: f.url.path)[.size] as? NSNumber)?.int64Value ?? 0
                let frames: String = scan.map { "\($0.frames)" } ?? "-"
                let tag: String = scan.map { $0.tag.rawValue } ?? "-"
                let tagFrames: String = scan?.tagFrameCount.map { "\($0)" } ?? "-"
                let trailing: String = scan.map { $0.trailingTags.isEmpty ? "-" : $0.trailingTags.joined(separator: ",") } ?? "-"
                let scanSeconds: String = d.scanSeconds.map { String(format: "%.3f", $0) } ?? "-"
                let precise: String = report.preciseDurationMs.map { "\($0)" } ?? "-"
                let estimated: String = report.estimatedDurationMs.map { "\($0)" } ?? "-"
                let scanned: String = scan?.audioDurationMs.map { "\($0)" } ?? "-"
                let cells: [String] = [f.label, report.codec ?? "-", report.timing.rawValue, oneLine(d.reason), frames, Self.bitRates(scan), tag,
                                       tagFrames, trailing, "\(bytes)", scanSeconds, String(format: "%.3f", report.inspectSeconds), precise, estimated, scanned]
                lines.append(cells.joined(separator: "\t"))
                #expect(report.timing == f.timing, "\(f.label): \(report.timing) (\(d.reason))")
                if let reason = f.reason { #expect(d.reason.contains(reason), "\(f.label): \(d.reason)") }
                if f.timing == .estimatedCBR, f.reason == "Info tag" {
                    #expect(scan?.tag == .info && scan?.tagFrameCount == scan.map { $0.frames - 1 }, "\(f.label): Info tag and its frame count")
                }
            }
            // Xing-tagged VBR files name both reasons.
            for f in ["fmt-mp3-vbr-xing.mp3", "long-mp3-vbr-10h.mp3"] {
                let reason = try await AssetInspector.inspect(try Fixtures.url(f)).timingDecision.reason
                #expect(reason.contains("Xing tag"), "\(f): \(reason)")
            }
        }

        /// Decoder windows (the excerpt export's path) with estimated and with precise timing in every proved-CBR
        /// fixture, against the masters and against each other.
        @Test("Estimated timing in proved-CBR MP3: decoder windows land where precise ones do; estimated timing in VBR MP3 and FLAC does not", .timeLimit(.minutes(20)))
        func decoderWindows() async throws {
            let master600 = try Fixtures.master600()
            let masterLong = try Fixtures.masterLong()
            var lines = ["# Decoder windows (AVAssetReader time range, the excerpt export's path) with estimated and precise timing. Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# error = true content position (cross-correlation with the master) minus the requested position (ms); sample_diff = the largest absolute",
                         "# difference between the estimated and the precise decode of the same window (0 = the same samples); decode_s = wall time of the decode",
                         "# (estimated on a fresh copy of the file, cold; precise on the fixture itself, which earlier tests may have opened)",
                         "kind\tfile\tpoint_s\testimated_error_ms\testimated_peak\tprecise_error_ms\tprecise_peak\tsample_diff\testimated_decode_s\tprecise_decode_s"]
            defer {
                lines.append("# at the end: \(Results.loadLabel())")
                Results.write("estimated-timing-decoder.tsv", lines)
            }
            let dir = try Self.scratch("est-decoder")
            defer { try? FileManager.default.removeItem(at: dir) }

            // The no-tag variant (a CBR stream whose Info frame was removed).
            let cbr = try Data(contentsOf: try Fixtures.url("fmt-mp3-cbr.mp3"))
            let frames = MP3Frames.list(cbr)
            var noTag = cbr
            noTag.removeSubrange(frames[0].offset..<frames[0].offset + frames[0].length)
            let noTagURL = dir.appendingPathComponent("cbr-no-info-tag.mp3")
            try noTag.write(to: noTagURL)

            struct Target {
                var label: String
                var url: () throws -> URL
                var master: any PCMSource
                var masterOffset: Double
                var loopFrames: Int?
                var points: [Double]
            }
            let fixture = { (f: String) in { try Fixtures.url(f) } }
            let targets: [Target] = [
                Target(label: "fmt-mp3-cbr.mp3", url: fixture("fmt-mp3-cbr.mp3"), master: master600, masterOffset: 0, points: [37.3, 151.7, 333.3, 587.2]),
                Target(label: "fmt-mp3-chap.mp3", url: fixture("fmt-mp3-chap.mp3"), master: master600, masterOffset: 0, points: [37.3, 333.3, 587.2]),
                Target(label: "variant: cbr-no-info-tag.mp3", url: { noTagURL }, master: master600, masterOffset: 0, points: [37.3, 333.3, 587.2]),
                Target(label: "fmt-librivox-mp3-22k.mp3", url: fixture("fmt-librivox-mp3-22k.mp3"), master: masterLong, masterOffset: 0, points: [37.3, 333.3, 900.5, 1_300.25]),
                Target(label: "multi/Part 1.mp3", url: fixture("multi/Part 1.mp3"), master: masterLong, masterOffset: 137.5, points: [20.5, 100.25, 150.0]),
                Target(label: "long-mp3-cbr-10h.mp3", url: fixture("long-mp3-cbr-10h.mp3"), master: masterLong, masterOffset: 0,
                       loopFrames: Fixtures.longLoopFrames, points: [3_601.3, 12_345.6, 18_000.7, 29_876.5, 34_170.0, 36_700.9]),
            ]
            var differences: [Double] = []
            for t in targets {
                let original = try t.url()
                let copy = dir.appendingPathComponent("est-\(UUID().uuidString.prefix(8))-\(original.lastPathComponent)")
                try FileManager.default.copyItem(at: original, to: copy)
                defer { try? FileManager.default.removeItem(at: copy) }
                for point in t.points {
                    var t0 = uptime()
                    let est = try await PCMDecoder.decode(url: copy, start: point, duration: 4, timing: .estimatedCBR)
                    let estSeconds = uptime() - t0
                    t0 = uptime()
                    let pre = try await PCMDecoder.decode(url: original, start: point, duration: 4, timing: .precise)
                    let preSeconds = uptime() - t0
                    let me = try #require(try TimingVerifier.measure(audio: est.samples, rate: est.sampleRate, intendedStart: t.masterOffset + point,
                                                                     master: t.master, loopFrames: t.loopFrames), "\(t.label) \(point): estimated unmeasurable")
                    let mp = try #require(try TimingVerifier.measure(audio: pre.samples, rate: pre.sampleRate, intendedStart: t.masterOffset + point,
                                                                     master: t.master, loopFrames: t.loopFrames), "\(t.label) \(point): precise unmeasurable")
                    let n = min(est.samples.count, pre.samples.count)
                    let diff = zip(est.samples.prefix(n), pre.samples.prefix(n)).map { abs($0 - $1) }.max() ?? .nan
                    lines.append(["proved-cbr", t.label, String(format: "%.2f", point), fmt(me.errorMs), fmt(me.peak), fmt(mp.errorMs), fmt(mp.peak),
                                  String(format: "%.6f", diff), String(format: "%.3f", estSeconds), String(format: "%.3f", preSeconds)].joined(separator: "\t"))
                    differences.append(abs(me.errorMs - mp.errorMs))
                    #expect(me.peak >= 0.5 && abs(me.errorMs) <= 500, "\(t.label) \(point): estimated \(me.errorMs) ms, peak \(me.peak)")
                    #expect(abs(me.errorMs - mp.errorMs) <= 1, "\(t.label) \(point): estimated \(me.errorMs) ms, precise \(mp.errorMs) ms")
                }
            }
            lines.append(String(format: "# proved-CBR windows: n=%d, |estimated - precise| max %.1f ms", differences.count, differences.max() ?? .nan))

            // Where the import never chooses estimated timing: VBR MP3 and native FLAC (with and without a seek table).
            // A window that lands more than 500 ms off, or whose content is not found within the search radius, is a
            // miss. Each file's metadata blocks show whether it has a seek table.
            struct Negative {
                var file: String
                var master: any PCMSource
                var loopFrames: Int?
                var points: [Double]
                var radius: Double
            }
            let negatives = [
                Negative(file: "fmt-mp3-vbr-xing.mp3", master: master600, loopFrames: nil, points: [151.7, 333.3, 587.2], radius: 30),
                Negative(file: "long-mp3-vbr-10h.mp3", master: masterLong, loopFrames: Fixtures.longLoopFrames, points: [12_345.6, 29_876.5, 34_170.0], radius: 150),
                Negative(file: "fmt-flac.flac", master: master600, loopFrames: nil, points: [151.7, 333.3, 587.2], radius: 30),
                Negative(file: "long-formats/long-flac-3h.flac", master: masterLong, loopFrames: Fixtures.longLoopFrames, points: [3_601.3, 9_000.5], radius: 150),
                Negative(file: "long-formats/long-flac-10h.flac", master: masterLong, loopFrames: Fixtures.longLoopFrames, points: [3_601.3, 18_000.7, 34_170.0], radius: 150),
            ]
            lines.append("kind\tfile\tpoint_s\testimated_error_ms(decoder, or 'not found within ±radius')\tpeak\tradius_s\tmetadata")
            for n in negatives {
                let original = try Fixtures.url(n.file)
                let copy = try Self.freshCopy(n.file, in: dir)
                defer { try? FileManager.default.removeItem(at: copy) }
                let metadata = n.file.hasSuffix(".flac") ? try FLACMetadata.blocks(original).joined(separator: ",") : "-"
                var misses = 0
                for point in n.points {
                    let est = try await PCMDecoder.decode(asset: AVURLAsset(url: copy), start: point, duration: 4)
                    let m = try TimingVerifier.measure(audio: est.samples, rate: est.sampleRate, intendedStart: point, master: n.master,
                                                       loopFrames: n.loopFrames, radiusSeconds: n.radius)
                    let found = (m?.peak ?? 0) >= 0.5
                    if !found || abs(m?.errorMs ?? .infinity) > 500 { misses += 1 }
                    lines.append(["estimated-not-chosen", n.file, String(format: "%.2f", point),
                                  found ? fmt(m!.errorMs) : "not found within ±\(Int(n.radius)) s", m.map { fmt($0.peak) } ?? "-",
                                  "\(Int(n.radius))", metadata].joined(separator: "\t"))
                }
                // The long VBR MP3 and the long FLAC files are where estimated timing must miss (the 10-minute ones are
                // recorded only: their misses are smaller, 0.56-2.9 s for the player in codec-matrix.tsv).
                if n.file.hasPrefix("long") {
                    #expect(misses > 0, "\(n.file): estimated timing landed within 500 ms at every window")
                }
            }
            // Native FLAC and estimated timing through the player (the resume path), on fresh copies.
            lines.append("kind\tfile\tpoint_s\tseek_to_audio_s\tstart_offset_ms(player, or 'not found')\tsteady_peak")
            for (file, points) in [("long-formats/long-flac-3h.flac", [3_601.3, 9_000.5]), ("long-formats/long-flac-10h.flac", [18_000.7, 34_170.0])] {
                let copy = try Self.freshCopy(file, in: dir)
                defer { try? FileManager.default.removeItem(at: copy) }
                let probe = PlayerProbe(url: copy, precise: false)
                #expect(try await probe.prepare(), "\(file): estimated item not ready")
                for point in points {
                    guard let r = try await probe.seekAndListen(to: point, listen: 2) else {
                        lines.append(["estimated-not-chosen-player", file, String(format: "%.2f", point), "-", "unmeasurable: \(probe.lastDiagnostic.prefix(80))", "-"].joined(separator: "\t"))
                        continue
                    }
                    let m = try PlayerProbe.measure(r, reference: masterLong, loopFrames: Fixtures.longLoopFrames, radiusSeconds: 150)
                    let found = (m.steadyPeak ?? 0) >= 0.5
                    lines.append(["estimated-not-chosen-player", file, String(format: "%.2f", point), r.startLatency.map { String(format: "%.3f", $0) } ?? "-",
                                  found ? (m.startOffsetMs.map { fmt($0) } ?? "-") : "not found within ±150 s", m.steadyPeak.map { fmt($0) } ?? "-"].joined(separator: "\t"))
                }
                probe.stop()
            }
        }

        /// The capture export, the pending preview and cross-file captures with the per-file timing mode, as the
        /// product opens them: the import's decision on the member, carried by the timeline and the capture service.
        @Test("Per-file timing mode on the capture paths: export and pending preview deep in a 10-hour CBR MP3, and across files", .timeLimit(.minutes(10)))
        func capturePaths() async throws {
            let masterLong = try Fixtures.masterLong()
            var lines = ["# Capture paths with the per-file timing mode (members opened as the import decided: estimatedCBR for these proved-CBR MP3 files).",
                         "# Environment: \(Results.environmentLabel()); at the start: \(Results.loadLabel())",
                         "# export: a capture (anchor write) then preserveExcerpt (decode, AAC encode, durable write) on a fresh copy, cold; errors against master-long (ms).",
                         "# preview: beginPreview of the pending source range on a fresh copy, cold; start_s = to the first buffer at the analysis tap.",
                         "kind\tfile\trange_s\tseconds\thead_err_ms\tseam_errs_ms\ttail_err_ms\tlength_err_ms\tplayer_end_ms\tpost_end_rms_ratio\tmin_peak\tload_1m"]
            defer {
                lines.append("# at the end: \(Results.loadLabel())")
                Results.write("estimated-timing-capture.tsv", lines)
            }
            let dir = try Self.scratch("est-capture")
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = "long-mp3-cbr-10h.mp3"
            let report = try await AssetInspector.inspect(try Fixtures.url(file))
            #expect(report.timing == .estimatedCBR)
            let durationMs = try #require(report.preciseDurationMs)

            // Exports at 1 h, 5 h and 9.5 h through the capture transaction, each on a fresh copy.
            for endMs: Int64 in [3_630_000, 18_030_000, 34_200_000] {
                let copy = try Self.freshCopy(file, in: dir)
                defer { try? FileManager.default.removeItem(at: copy) }
                let id = UUID()
                let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: file, durationMs: durationMs, timing: report.timing)])
                let store = try temporaryStore()
                let captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: { $0 == id ? copy : nil },
                                              resolveTiming: { $0 == id ? report.timing : .precise })
                let record = try captures.captureAudio(timeline: timeline, atGlobalMs: endMs, note: nil, idempotencyKey: UUID().uuidString)
                let t0 = uptime()
                let done = try await captures.preserveExcerpt(record.id)
                let seconds = uptime() - t0
                guard case .saved = done.excerpt else {
                    Issue.record("\(file) \(endMs): excerpt not preserved: \(done.excerpt)")
                    continue
                }
                let start = Double(endMs - 30_000) / 1000
                let m = try await ExcerptMeasure.measure(store.excerptURL(for: record.id), pieces: [.init(masterStart: start, duration: 30)],
                                                         master: masterLong, loopFrames: Fixtures.longLoopFrames)
                lines.append(["export", file, String(format: "%.1f-%.1f", start, start + 30), String(format: "%.3f", seconds), fmt(m.headErrorMs), "-",
                              fmt(m.tailErrorMs), fmt(m.lengthErrorMs), "-", "-", fmt(m.minPeak), Results.load1m()].joined(separator: "\t"))
                #expect(m.all.allSatisfy { abs($0) <= 500 } && m.minPeak >= 0.5, "\(file) export at \(endMs): \(m.all) ms")
            }

            // A pending preview 9.5 h in (8 s ending at 34,200 s), main paused at the start of the book.
            do {
                let copy = try Self.freshCopy(file, in: dir)
                defer { try? FileManager.default.removeItem(at: copy) }
                let id = UUID()
                let timeline = try EditionTimeline(editionID: UUID(), members: [EditionMember(assetID: id, fileName: file, durationMs: durationMs, timing: report.timing)])
                let p = RealPlayer()
                defer { p.stop() }
                await p.service.load(timeline: timeline, resolveFile: { $0 == id ? copy : nil })
                let segments = try #require(p.service.previewSegments(for: [AudioRange(assetID: id, startMs: 34_192_000, endMs: 34_200_000)]))
                #expect(segments.map(\.timing) == [.estimatedCBR])
                let r = try await Self.preview(p, segments: segments, masterOffsets: [0], master: masterLong)
                lines.append(["preview", file, "34192.0-34200.0", r.start.map { String(format: "%.3f", $0) } ?? "none", fmt(r.head), "-", "-", "-",
                              r.playerEnd.map { fmt($0) } ?? "-", String(format: "%.3f", r.postRatio), fmt(r.peak), Results.load1m()].joined(separator: "\t"))
                #expect(r.start != nil && abs(r.head) <= 500 && r.peak >= 0.5, "preview head \(r.head) ms, peak \(r.peak)")
                #expect(r.playerEnd.map { abs($0) <= 500 } == true, "preview player end \(String(describing: r.playerEnd)) ms")
                #expect(r.postRatio < 0.05, "audio past the intended end, rms ratio \(r.postRatio)")
            }

            // Across files: the multi-file book with every member as the import decided (estimatedCBR), a capture of the
            // preceding 30 s across each member boundary, exported and measured at head, seam and tail; and the pending
            // cross-file preview of the first.
            var members: [EditionMember] = []
            var urls: [UUID: URL] = [:]
            for m in Fixtures.multi {
                let url = try Fixtures.url("multi/\(m.name)")
                let r = try await AssetInspector.inspect(url)
                #expect(r.timing == .estimatedCBR, "\(m.name): \(r.timingDecision.reason)")
                let id = UUID()
                members.append(EditionMember(assetID: id, fileName: m.name, durationMs: try #require(r.preciseDurationMs), timing: r.timing))
                urls[id] = url
            }
            let book = try EditionTimeline(editionID: UUID(), members: members)
            let timings = Dictionary(uniqueKeysWithValues: members.map { ($0.assetID, $0.timing) })
            let byID = urls
            let resolve: @Sendable (UUID) -> URL? = { byID[$0] }
            let store = try temporaryStore()
            let captures = CaptureService(store: store, exporter: AACExcerptExporter(), resolveSource: resolve,
                                          resolveTiming: { timings[$0] ?? .precise })
            var firstRanges: [AudioRange]?
            for b in book.starts.dropFirst() {
                let record = try captures.captureAudio(timeline: book, atGlobalMs: b + 15_000, note: nil, idempotencyKey: UUID().uuidString)
                #expect(record.ranges.count == 2)
                if firstRanges == nil { firstRanges = record.ranges }
                let t0 = uptime()
                let done = try await captures.preserveExcerpt(record.id)
                let seconds = uptime() - t0
                guard case .saved = done.excerpt else {
                    Issue.record("cross-file at \(b): \(done.excerpt)")
                    continue
                }
                let pieces = try done.ranges.map { r in
                    let i = try #require(members.firstIndex { $0.assetID == r.assetID })
                    return ExcerptMeasure.Piece(masterStart: Fixtures.multi[i].start + Double(r.startMs) / 1000, duration: Double(r.durationMs) / 1000)
                }
                let m = try await ExcerptMeasure.measure(store.excerptURL(for: record.id), pieces: pieces, master: masterLong)
                lines.append(["export-cross-file", "multi (\(members.map(\.timing.rawValue).joined(separator: ",")))", String(format: "%.1f-%.1f (global)", Double(b - 15_000) / 1000, Double(b + 15_000) / 1000),
                              String(format: "%.3f", seconds), fmt(m.headErrorMs), m.seamErrorsMs.map { fmt($0) }.joined(separator: ","), fmt(m.tailErrorMs),
                              fmt(m.lengthErrorMs), "-", "-", fmt(m.minPeak), Results.load1m()].joined(separator: "\t"))
                #expect(m.all.allSatisfy { abs($0) <= 500 } && m.minPeak >= 0.5, "cross-file at \(b): \(m.all) ms")
            }
            let ranges = try #require(firstRanges)
            let p = RealPlayer()
            defer { p.stop() }
            await p.service.load(timeline: book, resolveFile: resolve)
            await p.service.seek(toGlobalMs: 400_000)
            let segments = try #require(p.service.previewSegments(for: ranges))
            #expect(segments.map(\.timing) == [.estimatedCBR, .estimatedCBR])
            let offsets = try ranges.map { r -> Double in
                let i = try #require(members.firstIndex { $0.assetID == r.assetID })
                return Fixtures.multi[i].start
            }
            let r = try await Self.preview(p, segments: segments, masterOffsets: offsets, master: masterLong)
            lines.append(["preview-cross-file", "multi", ranges.map { "\($0.startMs)-\($0.endMs) ms" }.joined(separator: " + "),
                          r.start.map { String(format: "%.3f", $0) } ?? "none", fmt(r.head), r.seams.map { fmt($0) }.joined(separator: ","), "-", "-",
                          r.playerEnd.map { fmt($0) } ?? "-", String(format: "%.3f", r.postRatio), fmt(r.peak), Results.load1m()].joined(separator: "\t"))
            #expect(r.start != nil && abs(r.head) <= 500 && r.peak >= 0.5)
            #expect(r.seams.count == 1 && r.seams.allSatisfy { abs($0) <= 500 })
            #expect(r.playerEnd.map { abs($0) <= 500 } == true)
            #expect(r.postRatio < 0.05)
        }

        struct PreviewResult {
            var start: Double?
            var head: Double
            var peak: Float
            var seams: [Double]
            var playerEnd: Double?
            var postRatio: Float
        }

        /// Previews `segments` with main paused and measures the head (content of the first rendered second against the
        /// master), each later segment's start, where the preview player stopped and the loudness past the intended end.
        /// `masterOffsets[i]`: where segment i's file starts in master-long.
        static func preview(_ p: RealPlayer, segments: [PreviewSegment], masterOffsets: [Double], master: MasterPCM) async throws -> PreviewResult {
            let first = segments[0], last = segments[segments.count - 1]
            let end = try #require(last.endSeconds)
            let total = segments.reduce(0) { $0 + (($1.endSeconds ?? 0) - $1.startSeconds) }
            let t0 = uptime()
            let ok = await p.service.beginPreview(segments)
            #expect(ok, "preview did not start: \(p.preview.lastFailure ?? "-")")
            let deadline = uptime() + total + 15
            while p.service.mode == .preview, uptime() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            #expect(p.service.mode == .main, "preview did not finish")
            await p.service.restoreTask?.value
            let start = p.previewCollectors[0]?.firstChunk(near: first.startSeconds, after: t0, tolerance: 0.5).map { $0.uptime - t0 }
            let run = try #require(p.previewCollectors[0]?.longestRun(near: first.startSeconds, after: t0, tolerance: 0.3), "head not rendered")
            let head = try #require(try contentErrorMs(run, masterOffset: masterOffsets[0], master: master, window: 1.0, loopFrames: Fixtures.longLoopFrames))
            var seams: [Double] = []
            for i in segments.indices.dropFirst() {
                let c = try #require(p.previewCollectors[i])
                let seamRun = try #require(c.longestRun(near: 0, after: t0, tolerance: 0.3), "segment \(i) not rendered")
                #expect(abs(seamRun.start) <= 0.01)
                let e = try #require(try contentErrorMs(seamRun, masterOffset: masterOffsets[i], master: master, window: 1.0))
                seams.append(e.errorMs)
            }
            let lastCollector = try #require(p.previewCollectors[segments.count - 1])
            let lastRun = try #require(lastCollector.tapRuns(after: t0).max { $0.end < $1.end })
            let cut = max(0, min(lastRun.samples.count, Int(((end - lastRun.start) * lastRun.rate).rounded())))
            let post = Array(lastRun.samples[cut...])
            let before = Array(lastRun.samples[..<cut])
            let postRatio = post.isEmpty ? 0 : rms(post) / max(rms(before), 1e-9)
            return PreviewResult(start: start, head: head.errorMs + (run.start - first.startSeconds) * 1000, peak: head.peak, seams: seams,
                                 playerEnd: p.preview.lastFinishSeconds.map { ($0 - end) * 1000 }, postRatio: postRatio)
        }
    }
}
