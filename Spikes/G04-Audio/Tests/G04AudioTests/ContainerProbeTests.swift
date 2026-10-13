import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

extension RealAV {
    /// Review R5-08: two container behaviours ADR-0006 relies on had been seen only in host probes made while the
    /// fixtures were built. These tests show them on the simulator and pin them, so a change in AVFoundation fails here:
    /// (1) which Vorbis-comment chapter numberings AVFoundation reads in native FLAC and Ogg Opus (the importer, and the
    /// fixtures, use the three-digit form), and (2) that AVAssetWriter takes MP3 packets unchanged in CAF but not in
    /// MPEG-4, which is why the import remux (ADR-0006 decision 17) puts a VBR MP3 into CAF.
    @Suite("Container probes: Vorbis-comment chapter numbering; MP3 packets in MPEG-4 and CAF (R5-08)")
    @MainActor
    struct ContainerProbeTests {
        /// The table every probe file carries (Scripts/fixtures/generate-g04-audio-probes.sh).
        static let table: [(title: String, startMs: Int64)] = [("Opening", 0), ("Chapter Two", 20_000), ("Chapter Three", 40_000)]
        /// Probe file stem, numbering, and whether AVFoundation is expected to read it (what this test pins).
        static let numberings: [(stem: String, numbering: String, read: Bool)] = [
            ("chapters-3digit-001", "CHAPTER001.. (three digits from 001)", true),
            ("chapters-3digit-000", "CHAPTER000.. (three digits from 000)", true),
            ("chapters-2digit-01", "CHAPTER01.. (two digits)", false),
        ]

        @Test("Vorbis-comment chapters by numbering, and MP3 packets in MPEG-4 and CAF", .timeLimit(.minutes(5)))
        func containerProbes() async throws {
            var lines = ["# Container probes (review R5-08). Environment: \(Results.environmentLabel())",
                         "## Vorbis-comment chapters by numbering: 60 s probes with the same table (Opening 0 s, Chapter Two 20 s, Chapter Three 40 s), read by AssetInspector.inspect",
                         "file\tnumbering\tchapters_read\tstarts_ms\ttitles\tlast_end_closed_at_duration\texpected"]
            defer { Results.write("container-probes.txt", lines) }
            for (stem, numbering, read) in Self.numberings {
                for ext in ["flac", "ogg"] {
                    let file = "probes/\(stem).\(ext)"
                    let report = try await AssetInspector.inspect(try Fixtures.url(file))
                    let chapters = report.chapters
                    lines.append([file, numbering, "\(chapters.count)", chapters.map { "\($0.startMs)" }.joined(separator: ","),
                                  chapters.map(\.title).joined(separator: ","), "\(report.chapterEndsClosedAtDuration)",
                                  read ? "read" : "not read"].joined(separator: "\t"))
                    #expect(report.isPlayable, "\(file) not playable")
                    if read {
                        #expect(chapters.map(\.title) == Self.table.map(\.title), "\(file): \(chapters.map(\.title))")
                        #expect(zip(chapters, Self.table).allSatisfy { abs($0.startMs - $1.startMs) <= 50 }, "\(file): \(chapters.map(\.startMs))")
                        // The last chapter's end is indefinite in Vorbis comments; the importer closes it at the duration.
                        #expect(report.chapterEndsClosedAtDuration == 1, "\(file): \(report.chapterEndsClosedAtDuration) ends closed")
                    } else {
                        #expect(chapters.isEmpty, "\(file): AVFoundation now reads \(chapters.count) chapters in the two-digit form")
                    }
                }
            }

            lines.append("## MP3 packets copied unchanged (ImportRemuxer.remux: AVAssetReader without output settings into AVAssetWriter without output settings)")
            lines.append("source\tcontainer\tresult\tdetail")
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("g04-probe-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            for name in ["fmt-mp3-vbr-xing.mp3", "fmt-mp3-vbr-noxing.mp3", "fmt-mp3-cbr.mp3"] {
                let source = try Fixtures.url(name)
                // MPEG-4: refused.
                do {
                    let r = try await ImportRemuxer.remux(source, to: dir.appendingPathComponent("\(name).m4a"), container: .mpeg4)
                    lines.append("\(name)\tmpeg4 (.m4a)\twritten\t\(r.sampleBuffers) sample buffers")
                    Issue.record("\(name): AVAssetWriter now takes MP3 packets in MPEG-4 (ADR-0006 decision 17 would not need CAF)")
                } catch {
                    lines.append("\(name)\tmpeg4 (.m4a)\trefused\t\(error)")
                }
                #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(name).m4a").path))
                // The same refusal for the .mp4 file type, asked directly.
                let asset = AVURLAsset(url: source)
                let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
                let format = try #require(try await track.load(.formatDescriptions).first)
                let writer = try AVAssetWriter(outputURL: dir.appendingPathComponent("\(name).mp4"), fileType: .mp4)
                let mp4Accepts = writer.canAdd(AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format))
                lines.append("\(name)\tmpeg4 (.mp4, AVAssetWriter.canAdd only)\t\(mp4Accepts ? "accepted" : "refused")\tcanAdd=\(mp4Accepts)")
                #expect(!mp4Accepts, "\(name): AVAssetWriter now takes MP3 packets in .mp4")
                // CAF: written, and the copy opens with the source's duration.
                let caf = dir.appendingPathComponent("\(name).caf")
                let r = try await ImportRemuxer.remux(source, to: caf, container: .caf)
                let sourceMs = try #require(try await AssetInspector.inspect(source).preciseDurationMs)
                let copyMs = try #require(try await AssetInspector.inspect(caf).preciseDurationMs)
                lines.append("\(name)\tcaf\twritten\t\(r.sampleBuffers) sample buffers, \(r.bytes) bytes, duration \(copyMs) ms (source \(sourceMs) ms)")
                #expect(abs(copyMs - sourceMs) <= 30, "\(name): CAF copy \(copyMs) ms, source \(sourceMs) ms")
            }
        }
    }
}
