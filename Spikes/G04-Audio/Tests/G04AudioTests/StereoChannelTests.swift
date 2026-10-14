import AVFoundation
import Foundation
import Testing
@testable import G04AudioKit

/// Reference PCM shifted by a frame offset: frame `f` of this source is frame `f + offset` of `base`.
struct ShiftedPCM: PCMSource {
    let base: any PCMSource
    let offset: Int
    var sampleRate: Double { base.sampleRate }
    func window(start: Int, count: Int) throws -> [Float] { try base.window(start: start + offset, count: count) }
}

/// A weighted sum of two references: the stereo master downmixed (0.5 left + 0.5 right).
struct MixPCM: PCMSource {
    let a: any PCMSource
    let b: any PCMSource
    let wa: Float
    let wb: Float
    var sampleRate: Double { a.sampleRate }
    func window(start: Int, count: Int) throws -> [Float] {
        let x = try a.window(start: start, count: count), y = try b.window(start: start, count: count)
        return zip(x, y).map { wa * $0 + wb * $1 }
    }
}

/// Decodes a file at the analysis rate into the given number of channels exactly as AVAssetReader delivers them
/// (two: both channels, nothing downmixed; one: the system two-to-one conversion, for comparison with the averaged
/// downmix of `PCMDecoder`), trimmed by presentation timestamp as `PCMDecoder` trims, with the time the decoder claims
/// for the start.
enum ChannelDecoder {
    static func decode(url: URL, start: Double, duration: Double, channels count: Int = 2,
                       rate: Double = PCMDecoder.analysisRate) async throws -> (channels: [[Float]], reportedStart: Double) {
        let asset = AssetInspector.preciseAsset(url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw PCMDecoderError.noAudioTrack }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw PCMDecoderError.cannotRead("\(error)") }
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1_000_000),
                                       duration: CMTime(seconds: duration, preferredTimescale: 1_000_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: PCMDecoder.outputSettings(rate: rate, channels: count))
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PCMDecoderError.cannotRead("cannot add output") }
        reader.add(output)
        guard reader.startReading() else { throw PCMDecoderError.cannotRead("\(String(describing: reader.error))") }
        let wanted = Int((duration * rate).rounded())
        var channels = [[Float]](repeating: [], count: count)
        for k in channels.indices { channels[k].reserveCapacity(wanted) }
        var reportedStart: Double?
        while let buffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let interleaved = PCMDecoder.floats(buffer)
            var skip = 0
            if reportedStart == nil {
                // Trim the frames the decoder delivered before the requested start (by its own timestamps).
                let early = Int(((start - pts) * rate).rounded())
                if early > 0 {
                    if early * count >= interleaved.count { continue }
                    skip = early
                    reportedStart = pts + Double(early) / rate
                } else {
                    reportedStart = pts
                }
            }
            var i = skip * count
            while i + count <= interleaved.count {
                for k in 0..<count { channels[k].append(interleaved[i + k]) }
                i += count
            }
            if channels[0].count >= wanted { break }
        }
        if reader.status == .failed { throw PCMDecoderError.readerFailed("\(String(describing: reader.error))") }
        reader.cancelReading()
        if channels[0].count > wanted {
            for k in channels.indices { channels[k].removeLast(channels[k].count - wanted) }
        }
        return (channels, reportedStart ?? start)
    }
}

/// Plays a stereo file in an AVPlayer with an analysis tap that keeps each channel, and returns what was rendered
/// after a zero-tolerance seek: the first contiguous run of at least 1.6 s at the target, per channel, at 44.1 kHz.
@MainActor
final class StereoPlayerProbe {
    let player = TestAudio.player()
    let collector = AudioTapCollector(keepsChannels: true)
    let item: AVPlayerItem
    var lastDiagnostic = ""

    init(url: URL) {
        item = AVPlayerItem(asset: AssetInspector.preciseAsset(url))
        item.audioTimePitchAlgorithm = AVQueuePlayerEngine.pitchAlgorithm
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func prepare() async throws -> Bool {
        try await AudioTap.attach(to: item, collector: collector)
        player.replaceCurrentItem(with: item)
        for _ in 0..<400 where item.status == .unknown { try await Task.sleep(for: .milliseconds(25)) }
        return item.status == .readyToPlay
    }

    struct Rendered {
        /// The source time the player reported for the first frame of the run.
        var reportedStart: Double
        /// Each channel of the run at 44.1 kHz.
        var channels: [[Float]]
        /// From play() to the first buffer at the target reaching the tap.
        var startLatency: Double?
    }

    func seekAndListen(to seconds: Double, listen: Double = 2.5) async throws -> Rendered? {
        player.pause()
        collector.reset()
        _ = await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 1_000_000), toleranceBefore: .zero, toleranceAfter: .zero)
        let t1 = ProcessInfo.processInfo.systemUptime
        player.playImmediately(atRate: 1)
        var startLatency: Double?
        for _ in 0..<1_500 {  // up to 15 s for the first buffer at the target
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
        lastDiagnostic = String(format: "start_latency_s=%@ chunks=", startLatency.map { String(format: "%.3f", $0) } ?? "none") + collector.describe()
        guard rate > 0, let first = chunks.firstIndex(where: { $0.uptime >= t1 && abs($0.sourceStart - seconds) < 1.0 }) else { return nil }
        // The first contiguous run of at least 1.6 s from the first buffer at the target (pre-roll buffers are skipped).
        var runStart = chunks[first].sourceStart
        var run: [[Float]] = chunks[first].channels
        var expectedNext = chunks[first].sourceStart + Double(chunks[first].samples.count) / rate
        var best: (start: Double, channels: [[Float]])?
        for c in chunks[(first + 1)...] where best == nil {
            if abs(c.sourceStart - expectedNext) < 0.002, c.channels.count == run.count {
                for k in run.indices { run[k].append(contentsOf: c.channels[k]) }
            } else {
                if let n = run.first?.count, Double(n) / rate >= 1.6 { best = (runStart, run) }
                runStart = c.sourceStart
                run = c.channels
            }
            expectedNext = c.sourceStart + Double(c.samples.count) / rate
        }
        if best == nil, let n = run.first?.count, Double(n) / rate >= 1.6 { best = (runStart, run) }
        guard let best, best.channels.count == 2 else { return nil }
        return Rendered(reportedStart: best.start,
                        channels: best.channels.map { Resampler.resample($0, from: rate, to: PCMDecoder.analysisRate) },
                        startLatency: startLatency)
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

extension RealAV {
    /// Review R6-05: every other G0.4 fixture is mono (the HE-AAC v2 one carries the mono master in both channels), so the
    /// matrix never showed what the decoder, the player and the excerpt export do with two different channels. The stereo
    /// master (`Scripts/fixtures/generate-g04-audio-stereo.sh`) has the first 300 s of master-600s.wav on the left and
    /// 300 s of master-long.wav from 1400 s (other words, same reader) on the right; each fixture is an encode of it.
    /// For every provisional format that can carry two channels: the channel count AVFoundation reports and the duration;
    /// zero-tolerance decoder seeks (both channels, nothing downmixed) and player seeks (each channel at the tap) put the
    /// left channel where the left reference is and the right where the right is, within the 500 ms budget, not swapped
    /// and not mixed (each channel correlates with its own reference, not with the other); the mono decode the excerpt
    /// export uses (`PCMDecoder`) is the average of the two channels (least-squares weights of the left and right
    /// references, 0.5 each); and exported excerpts (the preceding 30 s, clamped at the start, a 120 s extension) are
    /// within the budget at both ends against the averaged reference and hold both channels. Then the level: a file with
    /// the same speech in both channels (and the dual-mono HE-AAC v2 matrix file) keeps its level in the excerpt, where
    /// the system two-to-one conversion (what the export used before review 6) raises it by 3 dB.
    @Suite("Stereo sources with distinct channels (review R6-05)", .serialized)
    @MainActor
    struct StereoChannelTests {
        /// How a codec carries two channels, which decides what the channel checks expect.
        enum Stereo: String, Sendable {
            /// Two channels coded as such (independently, or as mid and side): each decoded channel is its own source.
            case discrete
            /// Parametric stereo (HE-AAC v2): one mono core plus level and phase parameters per band, from which the decoder
            /// makes two channels. Two different signals are not kept apart (each decoded channel is a mix of both; measured
            /// in the simulator), so channel identity is recorded, not judged; timing and the downmix are judged. AVFoundation
            /// reports the core channel count, 1, and the export decodes that one channel (`PCMDecoder`).
            case parametric
        }

        struct Format: Sendable {
            var id: String
            var file: String
            var label: String
            var stereo: Stereo = .discrete
            /// The channel count AVFoundation reports for the track.
            var reportedChannels = 2
        }

        static let formats: [Format] = [
            Format(id: "mp3-cbr", file: "st-mp3-cbr.mp3", label: "MP3 CBR 128 kb/s, joint stereo"),
            Format(id: "mp3-vbr-xing", file: "st-mp3-vbr-xing.mp3", label: "MP3 VBR, Xing/LAME header"),
            Format(id: "mp3-vbr-noxing", file: "st-mp3-vbr-noxing.mp3", label: "MP3 VBR, no Xing/VBRI header"),
            Format(id: "m4a-aac-lc", file: "st-m4a-aac-lc.m4a", label: "M4A AAC-LC 128 kb/s"),
            Format(id: "m4a-he-aac-v1", file: "st-m4a-heaac-v1.m4a", label: "M4A HE-AAC v1 64 kb/s"),
            Format(id: "m4a-he-aac-v2", file: "st-m4a-heaac-v2.m4a", label: "M4A HE-AAC v2 32 kb/s (parametric stereo)", stereo: .parametric,
                   reportedChannels: 1),
            Format(id: "m4a-alac", file: "st-m4a-alac.m4a", label: "M4A ALAC"),
            Format(id: "flac", file: "st-flac.flac", label: "FLAC (native container)"),
            Format(id: "mp4-flac", file: "st-mp4-flac.m4a", label: "FLAC in MP4"),
            Format(id: "ogg-opus", file: "st-opus.ogg", label: "Opus 64 kb/s in Ogg (.ogg)"),
            Format(id: "opus-ext", file: "st-opus.opus", label: "Opus 64 kb/s in Ogg (.opus)"),
            Format(id: "mp4-opus", file: "st-mp4-opus.m4a", label: "Opus 64 kb/s in MP4"),
            Format(id: "caf-opus", file: "st-caf-opus.caf", label: "Opus 64 kb/s in CAF"),
            Format(id: "wav", file: "master-stereo-300s.wav", label: "WAV PCM 16-bit (the stereo master)"),
        ]

        static let durationMs: Int64 = 300_000
        /// The right channel: master-long.wav from this frame (1400 s at 44.1 kHz; the generator states the same).
        static let rightOffsetFrames = 61_740_000
        static let budgetMs = 500.0
        static let durationToleranceMs: Int64 = 500
        static let decoderSeekPoints: [Double] = [1.75, 37.3, 151.7, 271.05, 291.2]
        static let playerSeekPoints: [Double] = [37.3, 151.7, 271.05]
        /// The preceding 30 s at an arbitrary point, a capture clamped at the start, and a 120-second extension.
        static let excerptSpans: [(start: Double, end: Double)] = [(121.37, 151.37), (0, 12.5), (155.55, 275.55)]
        /// A decoded or rendered channel of a discrete-stereo file correlates at least this much with its own reference,
        /// and at most `maximumOther` (in absolute value) with the other channel reference.
        static let minimumOwn: Float = 0.8
        static let maximumOther: Float = 0.2
        /// Mono audio made from a stereo source (the decode the excerpt export uses, and the excerpt itself): the
        /// least-squares weight of each channel. Discrete stereo is averaged, 0.5 each (lossy codecs a little less);
        /// HE-AAC v2 is its one-channel core, whose encoder mixes both channels with its own weights (recorded; both must
        /// be there).
        static func downmixWeightRange(_ stereo: Stereo) -> ClosedRange<Double> {
            switch stereo {
            case .discrete: 0.4...0.6
            case .parametric: 0.25...1.0
            }
        }
        /// The same speech in both channels keeps its level in the excerpt: least-squares gain against the source.
        static let sameSpeechGainRange: ClosedRange<Double> = 0.95...1.05

        struct ChannelMeasure {
            var errorMs: Double
            var peak: Float
            /// Normalized correlation with its own reference at the located position (1: the same signal up to gain).
            var own: Float
            /// The same with the reference of the other channel at that position (0: none of it).
            var other: Float
        }

        /// Locates one channel in its own reference and measures how much of the other channel it carries.
        static func measure(_ audio: [Float], intendedStart: Double, own: any PCMSource, other: any PCMSource,
                            scanSeconds: Double = 6) throws -> ChannelMeasure? {
            guard let m = try TimingVerifier.measure(audio: audio, rate: PCMDecoder.analysisRate, intendedStart: intendedStart,
                                                     master: own, scanSeconds: scanSeconds) else { return nil }
            let at = Int((m.actualStart * PCMDecoder.analysisRate).rounded())
            let ownReference = try own.window(start: at, count: audio.count)
            let otherReference = try other.window(start: at, count: audio.count)
            return ChannelMeasure(errorMs: m.errorMs, peak: m.peak, own: ncc(audio, ownReference), other: ncc(audio, otherReference))
        }

        /// Normalized correlation at zero lag.
        static func ncc(_ x: [Float], _ y: [Float]) -> Float {
            var xy = 0.0, xx = 0.0, yy = 0.0
            for i in 0..<min(x.count, y.count) {
                let a = Double(x[i]), b = Double(y[i])
                xy += a * b
                xx += a * a
                yy += b * b
            }
            return xx > 0 && yy > 0 ? Float(xy / (xx * yy).squareRoot()) : 0
        }

        /// The least-squares weights of the left and right references in mono audio `y` (y = l * left + r * right).
        static func weights(_ y: [Float], left: [Float], right: [Float]) -> (l: Double, r: Double) {
            var ll = 0.0, rr = 0.0, lr = 0.0, ly = 0.0, ry = 0.0
            for i in 0..<min(y.count, left.count, right.count) {
                let l = Double(left[i]), r = Double(right[i]), v = Double(y[i])
                ll += l * l
                rr += r * r
                lr += l * r
                ly += l * v
                ry += r * v
            }
            let det = ll * rr - lr * lr
            guard det > 0 else { return (.nan, .nan) }
            return ((ly * rr - ry * lr) / det, (ry * ll - ly * lr) / det)
        }

        /// Locates mono audio made from the stereo source against the downmixed reference, then weighs both channels in it.
        static func downmix(_ audio: [Float], intendedStart: Double, left: any PCMSource, right: any PCMSource, mix: any PCMSource,
                            scanSeconds: Double = 6) throws -> (errorMs: Double, peak: Float, l: Double, r: Double)? {
            guard let m = try TimingVerifier.measure(audio: audio, rate: PCMDecoder.analysisRate, intendedStart: intendedStart,
                                                     master: mix, scanSeconds: scanSeconds) else { return nil }
            let at = Int((m.actualStart * PCMDecoder.analysisRate).rounded())
            let w = weights(audio, left: try left.window(start: at, count: audio.count), right: try right.window(start: at, count: audio.count))
            return (m.errorMs, m.peak, w.l, w.r)
        }

        /// Whether a channel measurement meets what its stereo coding promises.
        static func channelProblem(_ m: ChannelMeasure, _ stereo: Stereo) -> String? {
            if abs(m.errorMs) > budgetMs { return "error \(fmt(m.errorMs)) ms" }
            switch stereo {
            case .discrete:
                if m.own < minimumOwn { return "own correlation \(fmt(m.own))" }
                if abs(m.other) > maximumOther { return "carries the other channel (\(fmt(m.other)))" }
            case .parametric:
                break  // channel identity recorded, not judged (see `Stereo.parametric`)
            }
            return nil
        }

        @Test("Stereo sources with distinct channels: decoder, player and excerpt export (simulator or device)", .timeLimit(.minutes(20)))
        func stereoChannels() async throws {
            let left = try Fixtures.master600()
            let right = ShiftedPCM(base: try Fixtures.masterLong(), offset: Self.rightOffsetFrames)
            let mix = MixPCM(a: left, b: right, wa: 0.5, wb: 0.5)
            var rows: [String] = [
                "# G0.4 stereo sources with distinct channels (review R6-05). Environment: \(Results.environmentLabel()). Budget: \(Int(Self.budgetMs)) ms.",
                "# Stereo master: left = master-600s.wav [0, 300 s), right = master-long.wav [1400 s, 1700 s): different speech in each channel. Fixtures: Scripts/fixtures/generate-g04-audio-stereo.sh.",
                "# err: content position minus intended position, ms (positive: the audio starts later in the source than intended). own: normalized correlation of a decoded or rendered channel with its own reference at that position; other: with the reference of the other channel (0: none of it).",
                "# w_left/w_right: least-squares weights of the left and right references in mono audio made from the source (0.5/0.5: the average of the two channels). Expected: discrete stereo own >= \(Self.minimumOwn), |other| <= \(Self.maximumOther) and weights \(Self.downmixWeightRange(.discrete).lowerBound)-\(Self.downmixWeightRange(.discrete).upperBound); parametric stereo (HE-AAC v2): channel identity recorded, not judged, weights \(Self.downmixWeightRange(.parametric).lowerBound)-\(Self.downmixWeightRange(.parametric).upperBound) (its one-channel core).",
                ["format", "file", "stereo", "playable", "codec", "rate", "channels", "precise_ms", "decoder_err_max_abs_ms", "decoder_own_min", "decoder_other_max_abs",
                 "mono_decode_w_left/w_right", "player_err_max_abs_ms", "player_own_min", "player_other_max_abs", "export_err_ms(start/end;...)", "export_w_left/w_right",
                 "verdict", "reasons"].joined(separator: "\t"),
            ]
            var detail: [String] = ["# detail", "format\tcheck\tpoint_s\tleft\tright\textra"]
            var failing: [String] = []

            for format in Self.formats {
                let url = try Fixtures.url("stereo/\(format.file)")
                var reasons: [String] = []
                var cells: [String] = [format.id, format.file, format.stereo.rawValue]

                // 1. Inspection: two channels and the duration.
                let report = try await AssetInspector.inspect(url)
                let playable = report.isPlayable && report.audioTrackCount > 0
                cells += [playable ? "yes" : "no", report.codec ?? "-", report.sampleRate.map { "\(Int($0))" } ?? "-",
                          report.channels.map(String.init) ?? "-", report.preciseDurationMs.map(String.init) ?? "-"]
                guard playable else {
                    failing.append(format.id)
                    rows.append((cells + ["-", "-", "-", "-", "-", "-", "-", "-", "-", "fail", "not playable"]).joined(separator: "\t"))
                    continue
                }
                if report.channels != format.reportedChannels {
                    reasons.append("AVFoundation reports \(report.channels.map(String.init) ?? "no") channels, \(format.reportedChannels) expected")
                }
                if let d = report.preciseDurationMs {
                    if abs(d - Self.durationMs) > Self.durationToleranceMs { reasons.append("duration \(d) ms") }
                } else { reasons.append("no duration") }

                // 2. Decoder seeks, both channels (AVAssetReader asked for two channels: nothing downmixed).
                var decoderErr = 0.0
                var decoderOwn: Float = 1, decoderOther: Float = 0
                for t in Self.decoderSeekPoints {
                    let d = try await ChannelDecoder.decode(url: url, start: t, duration: 4)
                    guard d.channels.count == 2, let l = try Self.measure(d.channels[0], intendedStart: t, own: left, other: right),
                          let r = try Self.measure(d.channels[1], intendedStart: t, own: right, other: left) else {
                        reasons.append("decoder seek \(t)s unmeasurable")
                        continue
                    }
                    decoderErr = max(decoderErr, abs(l.errorMs), abs(r.errorMs))
                    decoderOwn = min(decoderOwn, l.own, r.own)
                    decoderOther = max(decoderOther, abs(l.other), abs(r.other))
                    for (side, m) in [("left", l), ("right", r)] {
                        if let p = Self.channelProblem(m, format.stereo) { reasons.append("decoder \(side) at \(t)s: \(p)") }
                    }
                    detail.append("\(format.id)\tdecoder_seek\t\(t)\terr=\(fmt(l.errorMs)) own=\(fmt(l.own)) other=\(fmt(l.other))\terr=\(fmt(r.errorMs)) own=\(fmt(r.own)) other=\(fmt(r.other))\treported_start=\(fmt(d.reportedStart))")
                }
                cells += [fmt(decoderErr), fmt(decoderOwn), fmt(decoderOther)]

                // 3. The mono decode the excerpt export uses (PCMDecoder, one channel): it must hold both channels.
                var monoWeights: [String] = []
                for t in Self.playerSeekPoints {
                    let pcm = try await PCMDecoder.decode(url: url, start: t, duration: 4)
                    guard let w = try Self.downmix(pcm.samples, intendedStart: t, left: left, right: right, mix: mix) else {
                        reasons.append("mono decode at \(t)s unmeasurable")
                        continue
                    }
                    monoWeights.append("\(Self.f3(w.l))/\(Self.f3(w.r))")
                    if abs(w.errorMs) > Self.budgetMs { reasons.append("mono decode at \(t)s error \(fmt(w.errorMs)) ms") }
                    if !Self.downmixWeightRange(format.stereo).contains(w.l) || !Self.downmixWeightRange(format.stereo).contains(w.r) {
                        reasons.append("mono decode at \(t)s weights \(Self.f3(w.l))/\(Self.f3(w.r))")
                    }
                    detail.append("\(format.id)\tmono_decode\t\(t)\tw_left=\(Self.f3(w.l))\tw_right=\(Self.f3(w.r))\terr=\(fmt(w.errorMs)) peak=\(fmt(w.peak))")
                }
                cells.append(monoWeights.joined(separator: ";"))

                // 4. Player seeks: each channel as the tap receives it.
                var playerErr = 0.0
                var playerOwn: Float = 1, playerOther: Float = 0
                let probe = StereoPlayerProbe(url: url)
                if try await probe.prepare() {
                    for t in Self.playerSeekPoints {
                        guard let rendered = try await probe.seekAndListen(to: t) else {
                            reasons.append("player seek \(t)s unmeasurable [\(probe.lastDiagnostic)]")
                            continue
                        }
                        guard let l = try Self.measure(rendered.channels[0], intendedStart: rendered.reportedStart, own: left, other: right, scanSeconds: 0.75),
                              let r = try Self.measure(rendered.channels[1], intendedStart: rendered.reportedStart, own: right, other: left, scanSeconds: 0.75) else {
                            reasons.append("player channels at \(t)s unmeasurable")
                            continue
                        }
                        // Against the seek target as well: where the rendered audio really starts.
                        let offsets = [l, r].map { ($0.errorMs / 1000 + rendered.reportedStart - t) * 1000 }
                        playerErr = max(playerErr, abs(l.errorMs), abs(r.errorMs), offsets.map(abs).max() ?? 0)
                        playerOwn = min(playerOwn, l.own, r.own)
                        playerOther = max(playerOther, abs(l.other), abs(r.other))
                        for (side, m) in [("left", l), ("right", r)] {
                            if let p = Self.channelProblem(m, format.stereo) { reasons.append("player \(side) at \(t)s: \(p)") }
                        }
                        if let o = offsets.map(abs).max(), o > Self.budgetMs { reasons.append("player start offset at \(t)s \(fmt(o)) ms") }
                        detail.append("\(format.id)\tplayer_seek\t\(t)\terr=\(fmt(l.errorMs)) own=\(fmt(l.own)) other=\(fmt(l.other))\terr=\(fmt(r.errorMs)) own=\(fmt(r.own)) other=\(fmt(r.other))\tstart_offset_ms=\(fmt(offsets[0]))/\(fmt(offsets[1])) reported_start=\(fmt(rendered.reportedStart)) start_latency_s=\(rendered.startLatency.map { Self.f3($0) } ?? "-")")
                    }
                } else {
                    reasons.append("AVPlayerItem not ready: \(String(describing: probe.item.error))")
                }
                probe.stop()
                cells += [fmt(playerErr), fmt(playerOwn), fmt(playerOther)]

                // 5. Excerpt export (the product path: mono AAC .m4a), both ends against the downmixed reference.
                var exportCells: [String] = [], exportWeights: [String] = []
                for span in Self.excerptSpans {
                    let out = FileManager.default.temporaryDirectory.appendingPathComponent("g04-stereo-\(UUID().uuidString).m4a")
                    defer { try? FileManager.default.removeItem(at: out) }
                    let range = AudioRange(assetID: UUID(), startMs: Int64((span.start * 1000).rounded()), endMs: Int64((span.end * 1000).rounded()))
                    do {
                        _ = try await AACExcerptExporter().export([SourceSegment(url: url, range: range)], to: out)
                        let decoded = try await PCMDecoder.decode(url: out, start: 0, duration: nil)
                        guard let head = try Self.downmix(decoded.samples, intendedStart: span.start, left: left, right: right, mix: mix) else {
                            reasons.append("export \(span.start)-\(span.end): head unmeasurable")
                            exportCells.append("fail")
                            continue
                        }
                        let tailLength = min(Int(4 * PCMDecoder.analysisRate), decoded.samples.count)
                        let tail = Array(decoded.samples.suffix(tailLength))
                        let tailStart = span.end - Double(tailLength) / PCMDecoder.analysisRate
                        guard let end = try TimingVerifier.measure(audio: tail, rate: PCMDecoder.analysisRate, intendedStart: tailStart,
                                                                   master: mix, scanSeconds: 2.5) else {
                            reasons.append("export \(span.start)-\(span.end): tail unmeasurable")
                            exportCells.append("fail")
                            continue
                        }
                        exportCells.append("\(fmt(head.errorMs))/\(fmt(end.errorMs))")
                        exportWeights.append("\(Self.f3(head.l))/\(Self.f3(head.r))")
                        if abs(head.errorMs) > Self.budgetMs || abs(end.errorMs) > Self.budgetMs {
                            reasons.append("export \(span.start)-\(span.end) error \(fmt(head.errorMs))/\(fmt(end.errorMs)) ms")
                        }
                        if !Self.downmixWeightRange(format.stereo).contains(head.l) || !Self.downmixWeightRange(format.stereo).contains(head.r) {
                            reasons.append("export \(span.start)-\(span.end) weights \(Self.f3(head.l))/\(Self.f3(head.r))")
                        }
                        detail.append("\(format.id)\texport\t\(span.start)-\(span.end)\tw_left=\(Self.f3(head.l))\tw_right=\(Self.f3(head.r))\terr_start=\(fmt(head.errorMs)) err_end=\(fmt(end.errorMs)) peak_start=\(fmt(head.peak)) peak_end=\(fmt(end.peak))")
                    } catch {
                        reasons.append("export \(span.start)-\(span.end): \(error)")
                        exportCells.append("fail")
                    }
                }
                cells += [exportCells.joined(separator: ";"), exportWeights.joined(separator: ";")]

                let pass = reasons.isEmpty
                if !pass { failing.append(format.id) }
                rows.append((cells + [pass ? "pass" : "fail", oneLine(reasons.joined(separator: "; "))]).joined(separator: "\t"))
            }

            // 6. The same speech in both channels keeps its level in the excerpt (the averaged downmix). The system
            //    two-to-one conversion of the same source window is shown for comparison: it is what the export used
            //    before review 6, and it raises such a source by 3 dB.
            rows.append("# same speech in both channels: the excerpt 121.37-151.37 s against the left reference (master-600s.wav). export_gain: least-squares gain of the decoded excerpt; export_peak_ratio: its peak over the peak of the source over the same span; system_1ch_gain: the same gain for the system two-to-one conversion of the source window (AVAssetReader asked for one channel). Expected: export_gain \(Self.sameSpeechGainRange.lowerBound)-\(Self.sameSpeechGainRange.upperBound), export_peak_ratio at most 1.1.")
            rows.append(["same_speech_file", "reported_channels", "export_err_start_ms", "export_gain", "export_peak_ratio", "system_1ch_gain", "verdict"].joined(separator: "\t"))
            for file in ["stereo/st-dual-mono.flac", "fmt-m4a-heaac-v2.m4a"] {
                let url = try Fixtures.url(file)
                let span = (start: 121.37, end: 151.37)
                let report = try await AssetInspector.inspect(url)
                var problems: [String] = []
                var cells = [file, report.channels.map(String.init) ?? "-"]
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("g04-same-speech-\(UUID().uuidString).m4a")
                defer { try? FileManager.default.removeItem(at: out) }
                let range = AudioRange(assetID: UUID(), startMs: Int64((span.start * 1000).rounded()), endMs: Int64((span.end * 1000).rounded()))
                _ = try await AACExcerptExporter().export([SourceSegment(url: url, range: range)], to: out)
                let decoded = try await PCMDecoder.decode(url: out, start: 0, duration: nil)
                guard let head = try TimingVerifier.measure(audio: decoded.samples, rate: PCMDecoder.analysisRate,
                                                            intendedStart: span.start, master: left) else {
                    failing.append(file)
                    rows.append((cells + ["-", "-", "-", "-", "fail: unmeasurable"]).joined(separator: "\t"))
                    continue
                }
                let at = Int((head.actualStart * PCMDecoder.analysisRate).rounded())
                let reference = try left.window(start: at, count: decoded.samples.count)
                let gain = Self.gain(decoded.samples, reference)
                let peakRatio = Double(decoded.samples.map(abs).max() ?? 0) / Double(max(reference.map(abs).max() ?? 0, .leastNonzeroMagnitude))
                var systemGain = Double.nan
                let system = try await ChannelDecoder.decode(url: url, start: span.start, duration: span.end - span.start, channels: 1)
                if let s = try TimingVerifier.measure(audio: system.channels[0], rate: PCMDecoder.analysisRate, intendedStart: span.start, master: left) {
                    let sAt = Int((s.actualStart * PCMDecoder.analysisRate).rounded())
                    systemGain = Self.gain(system.channels[0], try left.window(start: sAt, count: system.channels[0].count))
                }
                if abs(head.errorMs) > Self.budgetMs { problems.append("error \(fmt(head.errorMs)) ms") }
                if !Self.sameSpeechGainRange.contains(gain) { problems.append("gain \(Self.f3(gain))") }
                if peakRatio > 1.1 { problems.append("peak ratio \(Self.f3(peakRatio))") }
                cells += [fmt(head.errorMs), Self.f3(gain), Self.f3(peakRatio), Self.f3(systemGain)]
                if !problems.isEmpty { failing.append(file) }
                rows.append((cells + [problems.isEmpty ? "pass" : "fail: " + problems.joined(separator: "; ")]).joined(separator: "\t"))
            }

            Results.write("stereo-channels.tsv", rows + detail)
            for id in failing { Issue.record("stereo format \(id) fails its channel checks; see stereo-channels.tsv") }
        }

        /// The least-squares gain of `y` against the reference `x` (y = g * x).
        static func gain(_ y: [Float], _ x: [Float]) -> Double {
            var xy = 0.0, xx = 0.0
            for i in 0..<min(x.count, y.count) {
                xy += Double(x[i]) * Double(y[i])
                xx += Double(x[i]) * Double(x[i])
            }
            return xx > 0 ? xy / xx : .nan
        }

        static func f3(_ x: Double) -> String { String(format: "%.3f", x) }
    }
}
