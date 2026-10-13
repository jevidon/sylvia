import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// Decoder portability of exported excerpts (G0.4 review: excerpts had been verified only with AVFoundation). The
/// excerpt timing test keeps copies of some exported excerpts in `G04_EXCERPTS_DIR` with a manifest. The CI drop-in
/// then decodes each with ffmpeg on the host (a decoder that shares no code with AVFoundation) into a 32-bit float
/// WAV, and `PortabilityTests` measures that decode against the PCM master exactly as the AVFoundation decode was
/// measured: cross-correlation at the head and at the tail.
enum ExcerptPortability {
    static let lock = NSLock()

    static func keep(_ file: URL, name: String, masterStart: Double, masterEnd: Double, avFoundationFrames: Int) {
        guard let value = ProcessInfo.processInfo.environment["G04_EXCERPTS_DIR"], !value.isEmpty else { return }
        guard value.hasPrefix("/") else {
            Issue.record("G04_EXCERPTS_DIR must be an absolute path, got '\(value)'")
            return
        }
        let dir = URL(fileURLWithPath: value, isDirectory: true)
        lock.withLock {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let copy = dir.appendingPathComponent("\(name).m4a")
                if FileManager.default.fileExists(atPath: copy.path) { try FileManager.default.removeItem(at: copy) }
                try FileManager.default.copyItem(at: file, to: copy)
                let manifest = dir.appendingPathComponent("manifest.tsv")
                let line = Data("\(name)\t\(masterStart)\t\(masterEnd)\t\(avFoundationFrames)\n".utf8)
                if FileManager.default.fileExists(atPath: manifest.path) {
                    let handle = try FileHandle(forWritingTo: manifest)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: manifest)
                }
            } catch {
                Issue.record("excerpt \(name) not kept for the portability check: \(error)")
            }
        }
    }
}

extension RealAV {
    @Suite("Excerpt decoder portability (ffmpeg)", .serialized)
    @MainActor
    struct PortabilityTests {
        static let budgetMs = 500.0

        /// Runs only in the CI drop-in's portability phase, after ffmpeg has decoded the kept excerpts; the drop-in
        /// fails if the phase does not produce `excerpt-portability.tsv`.
        @Test("Excerpts decoded by ffmpeg match the master at both ends",
              .enabled(if: ProcessInfo.processInfo.environment["G04_PORTABILITY_DIR"] != nil,
                       "runs in the portability phase of Scripts/ci.d/60-g04-audio.sh"),
              .timeLimit(.minutes(5)))
        func ffmpegDecodes() throws {
            let dir = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["G04_PORTABILITY_DIR"]), isDirectory: true)
            let master = try Fixtures.master600()
            let decoder = (try? String(contentsOf: dir.appendingPathComponent("decoder.txt"), encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let rows = try String(contentsOf: dir.appendingPathComponent("manifest.tsv"), encoding: .utf8)
                .split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
            var lines = ["# Exported excerpts (AAC .m4a, written by AVAudioFile) decoded by ffmpeg on the host, measured against master-600s. Excerpts exported on: \(Results.environmentLabel()). Decoder: \(decoder)",
                         "# head_err / end_err = true content position of the ffmpeg decode minus intended (ms, cross-correlation); avf_* = the same file decoded by AVFoundation",
                         "# ffmpeg_minus_avf_ms = decoded length difference (ffmpeg keeps trailing samples AVFoundation trims as encoder padding)",
                         "excerpt\tintended_s\thead_err_ms\tend_err_ms\tmin_peak\tffmpeg_length_err_ms\tffmpeg_minus_avf_ms"]
            defer { Results.write("excerpt-portability.tsv", lines) }
            let expected = CodecMatrixTests.provisionalReleaseList.count * 2
            #expect(rows.count == expected, "\(rows.count) kept excerpts, expected \(expected)")
            var heads: [Double] = [], ends: [Double] = [], extras: [Double] = []
            for row in rows {
                guard row.count == 4, let start = Double(row[1]), let end = Double(row[2]), let avfFrames = Int(row[3]) else {
                    Issue.record("malformed manifest row \(row)")
                    continue
                }
                let name = row[0]
                let pcm = try MasterPCM(url: dir.appendingPathComponent("\(name).ffmpeg.wav"))
                let rate = pcm.sampleRate
                #expect(rate == PCMDecoder.analysisRate, "\(name): ffmpeg decoded at \(rate) Hz")
                let samples = try pcm.window(start: 0, count: pcm.frameCount)
                let head = try #require(try TimingVerifier.measure(audio: samples, rate: rate, intendedStart: start, master: master),
                                        "\(name): head not measurable")
                let tailLength = min(Int(4 * rate), samples.count)
                let tail = try #require(try TimingVerifier.measure(audio: Array(samples.suffix(tailLength)), rate: rate,
                                                                   intendedStart: end - Double(tailLength) / rate, master: master,
                                                                   scanSeconds: 2.5),
                                        "\(name): tail not measurable")
                let endError = (tail.actualStart + Double(tailLength) / rate - end) * 1000
                let lengthError = (Double(samples.count) / rate - (end - start)) * 1000
                let extra = Double(samples.count - avfFrames) / rate * 1000
                heads.append(head.errorMs); ends.append(endError); extras.append(extra)
                lines.append("\(name)\t\(String(format: "%.3f-%.3f", start, end))\t\(fmt(head.errorMs))\t\(fmt(endError))\t\(fmt(min(head.peak, tail.peak)))\t\(fmt(lengthError))\t\(fmt(extra))")
                #expect(abs(head.errorMs) <= Self.budgetMs && abs(endError) <= Self.budgetMs, "\(name): \(head.errorMs) / \(endError) ms")
                #expect(min(head.peak, tail.peak) >= 0.5, "\(name): content mismatch")
            }
            lines.append(summary("ffmpeg decode head |error|", heads.map(abs), unit: "ms"))
            lines.append(summary("ffmpeg decode end |error|", ends.map(abs), unit: "ms"))
            lines.append(String(format: "ffmpeg minus AVFoundation decoded length: min %.1f ms, max %.1f ms", extras.min() ?? .nan, extras.max() ?? .nan))
        }
    }
}
