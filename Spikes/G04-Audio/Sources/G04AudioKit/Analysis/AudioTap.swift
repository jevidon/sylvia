import AVFoundation
import Foundation
import MediaToolbox

/// Collects the audio an AVPlayerItem actually renders, with the source time range the player reports for each
/// buffer (MTAudioProcessingTap). Analysis only: used by the G0.4 tests to measure seek accuracy, start latency
/// and preview boundaries. The tap sees source-rate audio before the time-pitch stage, so it shows which source
/// samples are played and when, not the pitch of the output.
public final class AudioTapCollector: @unchecked Sendable {
    public struct Chunk: Sendable {
        /// Source time of the first frame, in seconds, as reported to the tap.
        public var sourceStart: Double
        /// Mono samples (channels averaged).
        public var samples: [Float]
        /// Host uptime when the tap processed this chunk.
        public var uptime: TimeInterval
    }

    private let lock = NSLock()
    private var chunks: [Chunk] = []
    private var format = AudioStreamBasicDescription()
    private var recording = true

    public init() {}

    public var sampleRate: Double { lock.withLock { format.mSampleRate } }

    public func reset() { lock.withLock { chunks.removeAll() } }
    public func setRecording(_ on: Bool) { lock.withLock { recording = on } }
    public func snapshot() -> [Chunk] { lock.withLock { chunks } }

    fileprivate func prepare(_ asbd: AudioStreamBasicDescription) { lock.withLock { format = asbd } }

    fileprivate func append(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, start: CMTime) {
        guard frames > 0, start.isNumeric else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        lock.lock()
        defer { lock.unlock() }
        guard recording else { return }
        let abl = UnsafeMutableAudioBufferListPointer(list)
        let isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        guard isFloat, format.mBitsPerChannel == 32 else { return }
        var mono = [Float](repeating: 0, count: frames)
        if nonInterleaved {
            let n = abl.count
            for buffer in abl {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames { mono[i] += data[i] / Float(n) }
            }
        } else if let buffer = abl.first, let data = buffer.mData?.assumingMemoryBound(to: Float.self) {
            let ch = Int(buffer.mNumberChannels)
            for i in 0..<frames {
                var s: Float = 0
                for c in 0..<ch { s += data[i * ch + c] }
                mono[i] = s / Float(ch)
            }
        }
        chunks.append(Chunk(sourceStart: start.seconds, samples: mono, uptime: uptime))
    }

    /// Concatenates the chunks recorded since the last reset, starting at the first one, as long as each next
    /// chunk continues the previous one in source time (within 2 ms). Returns the reported start and the samples.
    public func contiguousAudio(maxSeconds: Double) -> (reportedStart: Double, samples: [Float], rate: Double)? {
        runs(maxSeconds: maxSeconds).first
    }

    /// All contiguous runs recorded since the last reset, in order.
    public func runs(maxSeconds: Double = .infinity) -> [(reportedStart: Double, samples: [Float], rate: Double)] {
        let chunks = snapshot()
        let rate = sampleRate
        guard rate > 0 else { return [] }
        var result: [(Double, [Float], Double)] = []
        var start = 0.0
        var samples: [Float] = []
        var expectedNext: Double?
        for c in chunks {
            if let e = expectedNext, abs(c.sourceStart - e) < 0.002 {
                if Double(samples.count) / rate < maxSeconds { samples.append(contentsOf: c.samples) }
            } else {
                if !samples.isEmpty { result.append((start, samples, rate)) }
                start = c.sourceStart
                samples = c.samples
            }
            expectedNext = c.sourceStart + Double(c.samples.count) / rate
        }
        if !samples.isEmpty { result.append((start, samples, rate)) }
        return result
    }

    /// A short description of the chunk sequence for diagnostics: source start and frames of the first chunks.
    public func describe(limit: Int = 6) -> String {
        snapshot().prefix(limit).map { String(format: "%.4f+%d", $0.sourceStart, $0.samples.count) }.joined(separator: " ")
    }
}

public enum AudioTapError: Error, Sendable {
    case noAudioTrack
    case createFailed(OSStatus)
}

public enum AudioTap {
    /// Attaches a tap that feeds `collector` to the item's first audio track.
    @MainActor
    public static func attach(to item: AVPlayerItem, collector: AudioTapCollector, postEffects: Bool = false) async throws {
        guard let track = try await item.asset.loadTracks(withMediaType: .audio).first else { throw AudioTapError.noAudioTrack }
        let params = AVMutableAudioMixInputParameters(track: track)
        try install(params, on: item, collector: collector, postEffects: postEffects)
    }

    /// Synchronous variant for items created inside the playback engine: the audio files used here have a single
    /// audio track, `trackID` (1 for every fixture; the async variant checks it).
    @MainActor
    public static func attach(to item: AVPlayerItem, trackID: CMPersistentTrackID, collector: AudioTapCollector, postEffects: Bool = false) throws {
        let params = AVMutableAudioMixInputParameters()
        params.trackID = trackID
        try install(params, on: item, collector: collector, postEffects: postEffects)
    }

    @MainActor
    private static func install(_ params: AVMutableAudioMixInputParameters, on item: AVPlayerItem, collector: AudioTapCollector, postEffects: Bool) throws {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(collector).toOpaque()),
            init: { _, clientInfo, storageOut in storageOut.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<AudioTapCollector>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<AudioTapCollector>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                var range = CMTimeRange()
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, &range, framesOut)
                guard status == noErr else { return }
                Unmanaged<AudioTapCollector>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .append(bufferList, frames: Int(framesOut.pointee), start: range.start)
            })
        var tap: MTAudioProcessingTap?
        let flags = postEffects ? kMTAudioProcessingTapCreationFlag_PostEffects : kMTAudioProcessingTapCreationFlag_PreEffects
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, flags, &tap)
        guard status == noErr, let tap else {
            Unmanaged<AudioTapCollector>.fromOpaque(callbacks.clientInfo!).release()
            throw AudioTapError.createFailed(status)
        }
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix
    }
}

/// Converts mono Float32 between sample rates with AVAudioConverter (for comparing 48 kHz Opus output with the
/// 44.1 kHz masters).
public enum Resampler {
    public static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard from != to, !x.isEmpty,
              let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(x.count)) else { return x }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        input.frameLength = AVAudioFrameCount(x.count)
        x.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: x.count) }
        let capacity = AVAudioFrameCount(Double(x.count) * to / from) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return x }
        nonisolated(unsafe) var supplied = false
        nonisolated(unsafe) let source = input
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
