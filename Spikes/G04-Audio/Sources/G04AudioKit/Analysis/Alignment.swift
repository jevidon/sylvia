import Accelerate
import AVFoundation
import Foundation

/// Locates a short probe of decoded audio inside reference PCM by normalized cross-correlation (NCC). Used to
/// measure where decoded, played or exported audio really comes from, independently of any timestamp.
public enum Alignment {
    public struct Match: Sendable, Equatable {
        /// Offset of the probe's first sample inside the reference, in samples.
        public var offset: Int
        /// Normalized correlation at that offset (1 means identical up to gain).
        public var peak: Float
    }

    /// Searches lags `expected - radius ... expected + radius` (clamped to the reference). Two stages: a coarse
    /// search on 8x box-decimated signals, then a sample-accurate search around the coarse winner.
    public static func locate(probe: [Float], in reference: [Float], expected: Int, radius: Int) -> Match? {
        let p = probe.count
        guard p > 64, reference.count >= p else { return nil }
        let lo = max(0, expected - radius), hi = min(reference.count - p, expected + radius)
        guard lo <= hi else { return nil }

        let d = 8
        let pd = decimate(probe, d), rd = decimate(Array(reference[(lo)..<min(reference.count, hi + p)]), d)
        var coarseBest = lo
        if rd.count >= pd.count, pd.count > 8 {
            let lags = rd.count - pd.count + 1
            var corr = [Float](repeating: 0, count: lags)
            pd.withUnsafeBufferPointer { pb in
                rd.withUnsafeBufferPointer { rb in
                    vDSP_conv(rb.baseAddress!, 1, pb.baseAddress!, 1, &corr, 1, vDSP_Length(lags), vDSP_Length(pd.count))
                }
            }
            let energies = slidingEnergy(rd, window: pd.count)
            let pe = energy(pd)
            var bestScore: Float = -2
            for k in 0..<lags {
                let denom = (pe * energies[k]).squareRoot()
                let score = denom > 0 ? corr[k] / denom : 0
                if score > bestScore { bestScore = score; coarseBest = lo + k * d }
            }
        }
        // Fine search, full rate, around the coarse winner.
        let flo = max(lo, coarseBest - 2 * d), fhi = min(hi, coarseBest + 2 * d)
        let pe = energy(probe)
        var best = Match(offset: flo, peak: -2)
        probe.withUnsafeBufferPointer { pb in
            reference.withUnsafeBufferPointer { rb in
                for lag in flo...fhi {
                    var dot: Float = 0
                    vDSP_dotpr(pb.baseAddress!, 1, rb.baseAddress! + lag, 1, &dot, vDSP_Length(p))
                    var e: Float = 0
                    vDSP_svesq(rb.baseAddress! + lag, 1, &e, vDSP_Length(p))
                    let denom = (pe * e).squareRoot()
                    let score = denom > 0 ? dot / denom : 0
                    if score > best.peak { best = Match(offset: lag, peak: score) }
                }
            }
        }
        return best
    }

    static func decimate(_ x: [Float], _ d: Int) -> [Float] {
        let n = x.count / d
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        x.withUnsafeBufferPointer { xb in
            for i in 0..<n {
                var s: Float = 0
                vDSP_sve(xb.baseAddress! + i * d, 1, &s, vDSP_Length(d))
                out[i] = s / Float(d)
            }
        }
        return out
    }

    static func energy(_ x: [Float]) -> Float {
        var e: Float = 0
        vDSP_svesq(x, 1, &e, vDSP_Length(x.count))
        return e
    }

    static func slidingEnergy(_ x: [Float], window: Int) -> [Float] {
        let lags = x.count - window + 1
        guard lags > 0 else { return [] }
        var prefix = [Double](repeating: 0, count: x.count + 1)
        for i in 0..<x.count { prefix[i + 1] = prefix[i] + Double(x[i]) * Double(x[i]) }
        return (0..<lags).map { Float(prefix[$0 + window] - prefix[$0]) }
    }

    /// Index of the loudest `length`-sample window starting in `[0, maxStart]`, stepping by `step` samples.
    /// Probes are taken from speech rather than from a pause, where correlation is meaningless.
    public static func loudestWindow(_ x: [Float], length: Int, maxStart: Int, step: Int) -> Int {
        guard x.count >= length else { return 0 }
        let limit = min(maxStart, x.count - length)
        var bestStart = 0
        var bestEnergy: Float = -1
        var s = 0
        while s <= limit {
            var e: Float = 0
            x.withUnsafeBufferPointer { vDSP_svesq($0.baseAddress! + s, 1, &e, vDSP_Length(length)) }
            if e > bestEnergy { bestEnergy = e; bestStart = s }
            s += step
        }
        return bestStart
    }
}

/// Random access to reference PCM by absolute frame index.
public protocol PCMSource: Sendable {
    var sampleRate: Double { get }
    /// Samples `[start, start + count)`; positions outside the source are returned as silence.
    func window(start: Int, count: Int) throws -> [Float]
}

/// Reference PCM held in memory whose first sample sits at absolute frame `originFrame`.
public struct ArrayPCMSource: PCMSource {
    public var samples: [Float]
    public var originFrame: Int
    public var sampleRate: Double
    public init(samples: [Float], originFrame: Int, sampleRate: Double) {
        self.samples = samples
        self.originFrame = originFrame
        self.sampleRate = sampleRate
    }
    public func window(start: Int, count: Int) throws -> [Float] {
        (0..<count).map { i in
            let j = start + i - originFrame
            return j >= 0 && j < samples.count ? samples[j] : 0
        }
    }
}

/// Sample-exact random access to a 44.1 kHz mono WAV master (the source of every generated fixture).
public final class MasterPCM: PCMSource, @unchecked Sendable {
    // AVAudioFile is not Sendable; access is serialized by `lock`.
    private let file: AVAudioFile
    private let lock = NSLock()
    public let frameCount: Int
    public let sampleRate: Double

    public init(url: URL) throws {
        file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        frameCount = Int(file.length)
        sampleRate = file.processingFormat.sampleRate
    }

    /// Samples `[start, start + count)`; positions outside the file are returned as silence.
    public func window(start: Int, count: Int) throws -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        var out = [Float](repeating: 0, count: count)
        let s = max(0, start), e = min(frameCount, start + count)
        guard s < e else { return out }
        file.framePosition = AVAudioFramePosition(s)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(e - s)) else { return out }
        try file.read(into: buffer, frameCount: AVAudioFrameCount(e - s))
        let n = Int(buffer.frameLength)
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<n { out[s - start + i] = ch[i] }
        }
        return out
    }
}

/// Measures where a piece of decoded audio really starts, in master time.
public enum TimingVerifier {
    public struct Measurement: Sendable, Codable, Equatable {
        /// Where the audio was meant to start, in master seconds.
        public var intendedStart: Double
        /// Where the audio actually starts according to cross-correlation, in master seconds.
        public var actualStart: Double
        /// `actualStart - intendedStart`, in milliseconds. Positive: the audio starts late (content is missing at
        /// the head); negative: it starts early (extra content at the head).
        public var errorMs: Double
        public var peak: Float
    }

    /// `audio` starts (per its producer) at `intendedStart` seconds of the master. `loopFrames` folds positions of
    /// looped fixtures back into the master. A probe of `probeSeconds` is taken from the loudest window in the first
    /// `scanSeconds` of the audio and searched within `radiusSeconds` of where it should be.
    public static func measure(audio: [Float], rate: Double, intendedStart: Double, master: any PCMSource,
                               loopFrames: Int? = nil, probeSeconds: Double = 1.5, scanSeconds: Double = 6,
                               radiusSeconds: Double = 3) throws -> Measurement? {
        precondition(rate == master.sampleRate, "analysis rate must match the master")
        let probeLen = Int(probeSeconds * rate)
        guard audio.count >= probeLen else { return nil }
        let probeAt = Alignment.loudestWindow(audio, length: probeLen, maxStart: Int(scanSeconds * rate), step: Int(0.25 * rate))
        let probe = Array(audio[probeAt..<probeAt + probeLen])
        var expected = Int((intendedStart * rate).rounded()) + probeAt
        var foldedBase = 0
        if let loopFrames {
            foldedBase = (expected / loopFrames) * loopFrames
            expected -= foldedBase
        }
        let radius = Int(radiusSeconds * rate)
        let refStart = expected - radius
        let reference = try master.window(start: refStart, count: 2 * radius + probeLen)
        guard let match = Alignment.locate(probe: probe, in: reference, expected: radius, radius: radius) else { return nil }
        let actualProbeStart = refStart + match.offset + foldedBase
        let actualStart = Double(actualProbeStart - probeAt) / rate
        return Measurement(intendedStart: intendedStart, actualStart: actualStart,
                           errorMs: (actualStart - intendedStart) * 1000, peak: match.peak)
    }
}
