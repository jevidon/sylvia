import AVFoundation
import Foundation
@testable import G04AudioKit

/// Plays an asset in an AVPlayer with an analysis tap and reports what was really rendered after a seek.
@MainActor
final class PlayerProbe {
    let player = TestAudio.player()
    let collector = AudioTapCollector()
    let item: AVPlayerItem
    var lastDiagnostic = ""

    struct SeekResult {
        var requested: Double
        var seekFinished: Bool
        /// `currentTime()` right after the zero-tolerance seek completed.
        var currentTimeAfterSeek: Double
        /// Source time of the first rendered buffer, as reported to the tap.
        var reportedStart: Double
        /// The steady run, mono, at the analysis rate (44.1 kHz).
        var samples: [Float]
        /// Buffers the tap processed before the first buffer at the seek target (pre-roll from the old position).
        var precedingRuns: Int
        var diagnostic: String
        /// The first buffer at the target (analysis rate).
        var firstBuffer: [Float]
        /// Reported start of the steady run measured in `samples`.
        var steadyReportedStart: Double
        var seekSeconds: Double
        /// From play() to the first buffer at the target reaching the tap.
        var startLatency: Double?
    }

    init(url: URL, precise: Bool = true) {
        item = AVPlayerItem(asset: precise ? AssetInspector.preciseAsset(url) : AVURLAsset(url: url))
        item.audioTimePitchAlgorithm = AVQueuePlayerEngine.pitchAlgorithm
        player.automaticallyWaitsToMinimizeStalling = false
    }

    /// Attaches the tap and waits for the item to become ready. Returns false when the item fails.
    func prepare() async throws -> Bool {
        try await AudioTap.attach(to: item, collector: collector)
        player.replaceCurrentItem(with: item)
        for _ in 0..<400 where item.status == .unknown { try await Task.sleep(for: .milliseconds(25)) }
        return item.status == .readyToPlay
    }

    /// Seeks with zero tolerance, plays for `listen` seconds after the first buffer at the target is processed,
    /// and measures two things from the tap:
    /// - `firstBuffer`: the first buffer whose reported start is at the target. Its content position says where
    ///   playback really starts after the seek.
    /// - `steady`: the first contiguous run of at least one second after that buffer. Its content position checks
    ///   that the times the player reports while playing are true.
    /// The tap also sees buffers the player pre-rolls while paused (from before the seek, and the target buffer
    /// processed twice with overlapping frames); they are counted, not measured.
    func seekAndListen(to seconds: Double, listen: Double = 2.5) async throws -> SeekResult? {
        player.pause()
        collector.reset()
        let t0 = ProcessInfo.processInfo.systemUptime
        let finished = await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1_000_000),
                                         toleranceBefore: .zero, toleranceAfter: .zero)
        let seekSeconds = ProcessInfo.processInfo.systemUptime - t0
        let after = player.currentTime().seconds
        let t1 = ProcessInfo.processInfo.systemUptime
        player.playImmediately(atRate: 1)
        var startLatency: Double?
        for _ in 0..<1_500 {  // up to 15 s for the first buffer at the target
            // Only buffers the tap processed after play(): pre-roll buffers rendered during the paused seek do not
            // count as playback having started.
            if let c = collector.snapshot().first(where: { $0.uptime >= t1 && abs($0.sourceStart - seconds) < 1.0 }) {
                startLatency = c.uptime - t1
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .seconds(listen))
        player.pause()
        let chunks = collector.snapshot()
        let rate = collector.sampleRate
        let diagnostic = String(format: "seek_s=%.3f start_latency_s=%@ chunks=", seekSeconds, startLatency.map { String(format: "%.3f", $0) } ?? "none") + collector.describe()
        lastDiagnostic = diagnostic
        guard rate > 0, let first = chunks.firstIndex(where: { abs($0.sourceStart - seconds) < 1.0 }) else { return nil }
        // Steady run: the first contiguous run of >= 1 s at or after the first target buffer, skipping repeats.
        var best: (start: Double, samples: [Float])?
        var runStart = chunks[first].sourceStart
        var run: [Float] = []
        var expectedNext: Double?
        for c in chunks[first...] {
            if let e = expectedNext, abs(c.sourceStart - e) < 0.002 {
                run.append(contentsOf: c.samples)
            } else {
                if Double(run.count) / rate >= 1.0 { best = (runStart, run); break }
                runStart = c.sourceStart
                run = c.samples
            }
            expectedNext = c.sourceStart + Double(c.samples.count) / rate
        }
        if best == nil, Double(run.count) / rate >= 1.0 { best = (runStart, run) }
        guard let best else { return nil }
        return SeekResult(requested: seconds, seekFinished: finished, currentTimeAfterSeek: after,
                          reportedStart: chunks[first].sourceStart,
                          samples: Resampler.resample(best.samples, from: rate, to: PCMDecoder.analysisRate),
                          precedingRuns: first, diagnostic: diagnostic,
                          firstBuffer: Resampler.resample(chunks[first].samples, from: rate, to: PCMDecoder.analysisRate),
                          steadyReportedStart: best.start, seekSeconds: seekSeconds, startLatency: startLatency)
    }

    struct SeekMeasurement {
        /// Content position of the steady run minus the position the player reported for it (ms). Checks that
        /// the player's own clock is true while it plays.
        var steadyErrorMs: Double?
        var steadyPeak: Float?
        /// True source position where the first continuous second of audio begins, minus the seek target (ms).
        /// An upper bound on how late audio at the target starts; buffers before it are pre-roll the tap cannot
        /// attribute to the output.
        var startOffsetMs: Double?
        /// Content position of the first buffer reported at the target, minus the target (diagnostic only; the
        /// tap also sees silent and repeated pre-roll buffers there).
        var firstBufferErrorMs: Double?
        var firstBufferPeak: Float?
    }

    static func measure(_ r: SeekResult, reference: any PCMSource, loopFrames: Int? = nil, radiusSeconds: Double = 3) throws -> SeekMeasurement {
        let first = try TimingVerifier.measure(audio: r.firstBuffer, rate: PCMDecoder.analysisRate, intendedStart: r.requested,
                                               master: reference, loopFrames: loopFrames, probeSeconds: 0.05, scanSeconds: 0.04, radiusSeconds: 1)
        let steady = try TimingVerifier.measure(audio: r.samples, rate: PCMDecoder.analysisRate, intendedStart: r.steadyReportedStart,
                                                master: reference, loopFrames: loopFrames, scanSeconds: 0.75, radiusSeconds: radiusSeconds)
        return SeekMeasurement(steadyErrorMs: steady?.errorMs, steadyPeak: steady?.peak,
                               startOffsetMs: steady.map { ($0.actualStart - r.requested) * 1000 },
                               firstBufferErrorMs: first?.errorMs, firstBufferPeak: first?.peak)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Exports excerpts and measures the exported range against the master by cross-correlation.
enum ExcerptProbe {
    struct Result: Sendable {
        var intendedStart: Double
        var intendedEnd: Double
        var exported: ExportedExcerpt
        var startErrorMs: Double
        var endErrorMs: Double
        var startPeak: Float
        var endPeak: Float
        /// Decoded output length minus intended length, in ms.
        var lengthErrorMs: Double
        /// What the exporter claimed as the actual start (decoder timestamps) minus the intended start, in ms.
        var claimedStartOffsetMs: Double
        /// Wall time of the export itself (decode, encode, durable write), without the measurement.
        var exportSeconds: Double = 0
    }

    struct Unmeasurable: Error, CustomStringConvertible {
        var description: String
    }

    /// `segments` are file-local ranges; `masterStart`/`masterEnd` are where they map in master time. `keep` names
    /// a copy of the exported file for the decoder-portability check (`ExcerptPortability`), when that is enabled.
    static func run(_ segments: [SourceSegment], masterStart: Double, masterEnd: Double, master: any PCMSource,
                    loopFrames: Int? = nil, keep: String? = nil) async throws -> Result {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("g04-excerpt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: out) }
        let exportStarted = ProcessInfo.processInfo.systemUptime
        let exported = try await AACExcerptExporter().export(segments, to: out)
        let exportSeconds = ProcessInfo.processInfo.systemUptime - exportStarted
        let decoded = try await PCMDecoder.decode(url: out, start: 0, duration: nil)
        if let keep {
            ExcerptPortability.keep(out, name: keep, masterStart: masterStart, masterEnd: masterEnd, avFoundationFrames: decoded.samples.count)
        }
        let rate = decoded.sampleRate
        guard let head = try TimingVerifier.measure(audio: decoded.samples, rate: rate, intendedStart: masterStart,
                                                    master: master, loopFrames: loopFrames) else {
            throw Unmeasurable(description: "head of excerpt not measurable")
        }
        let tailLength = min(Int(4 * rate), decoded.samples.count)
        let tail = Array(decoded.samples.suffix(tailLength))
        let intendedTailStart = masterEnd - Double(tailLength) / rate
        guard let end = try TimingVerifier.measure(audio: tail, rate: rate, intendedStart: intendedTailStart,
                                                   master: master, loopFrames: loopFrames, scanSeconds: 2.5) else {
            throw Unmeasurable(description: "tail of excerpt not measurable")
        }
        let actualEnd = end.actualStart + Double(tailLength) / rate
        let claimed = exported.actualRanges.first.map { Double($0.startMs) / 1000 - Double(segments[0].range.startMs) / 1000 } ?? 0
        return Result(intendedStart: masterStart, intendedEnd: masterEnd, exported: exported,
                      startErrorMs: head.errorMs, endErrorMs: (actualEnd - masterEnd) * 1000,
                      startPeak: head.peak, endPeak: end.peak,
                      lengthErrorMs: (decoded.durationSeconds - (masterEnd - masterStart)) * 1000,
                      claimedStartOffsetMs: claimed * 1000, exportSeconds: exportSeconds)
    }
}

/// Sequential decode from the start of a file, keeping only requested windows. Positions are counted in decoded
/// samples, not taken from timestamps or seeks, so the windows are a reference for files without a master.
enum SequentialReference {
    static func windows(url: URL, _ windows: [(start: Double, duration: Double)], rate: Double = PCMDecoder.analysisRate) async throws -> [[Float]] {
        let asset = AssetInspector.preciseAsset(url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw PCMDecoderError.noAudioTrack }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: PCMDecoder.outputSettings(rate: rate))
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw PCMDecoderError.cannotRead("\(String(describing: reader.error))") }
        let ranges = windows.map { (Int($0.start * rate), Int(($0.start + $0.duration) * rate)) }
        var result = Array(repeating: [Float](), count: windows.count)
        let lastEnd = ranges.map(\.1).max() ?? 0
        var position = 0
        while position < lastEnd, let buffer = output.copyNextSampleBuffer() {
            let chunk = PCMDecoder.floats(buffer)
            let chunkEnd = position + chunk.count
            for (i, r) in ranges.enumerated() where r.0 < chunkEnd && r.1 > position {
                let s = max(r.0, position) - position, e = min(r.1, chunkEnd) - position
                result[i].append(contentsOf: chunk[s..<e])
            }
            position = chunkEnd
        }
        reader.cancelReading()
        return result
    }
}
