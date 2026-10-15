import Accelerate
import AVFoundation
import Foundation

/// Decoded mono PCM and the asset time the decoder claims for its first sample.
public struct DecodedPCM: Sendable {
    public var samples: [Float]
    public var sampleRate: Double
    /// Asset time, in seconds, that the decoder's presentation timestamps assign to `samples[0]`.
    public var reportedStart: Double
    /// The source track's format as `codec/sample rate/channels` (for example `.mp3/22050/1`, `aac /44100/1`).
    public var sourceFormat: String = "unknown"
    public var durationSeconds: Double { Double(samples.count) / sampleRate }

    /// `codec/sample rate/channels` from a track's first format description.
    static func describe(_ track: AVAssetTrack) async -> String {
        guard let desc = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return "unknown" }
        return "\(AssetInspector.fourCC(asbd.mFormatID))/\(Int(asbd.mSampleRate))/\(asbd.mChannelsPerFrame)"
    }
}

public enum PCMDecoderError: Error, Sendable {
    case noAudioTrack
    case cannotRead(String)
    case readerFailed(String)
}

/// Decodes a window of an audio asset with AVAssetReader (the same decoder stack the exporter uses) into mono
/// Float32 at a fixed analysis rate. Samples before the requested start are trimmed by presentation timestamp, so
/// `reportedStart` is the decoder's own claim about where the returned audio begins. Whether that claim is true is
/// what the timing tests measure by cross-correlation against the PCM masters.
///
/// Mono from a stereo source is the average of the two channels, (L + R) / 2 (review R6-05): never louder than the
/// louder channel, so never above full scale, and speech that is the same in both channels keeps its level. A source
/// the system reports with one channel (mono, and HE-AAC v2, whose core is one channel plus parametric stereo) is
/// decoded to one channel, at unity (measured: 1.000 for mono files, 0.993 for the HE-AAC v2 fixture); a source with
/// more channels is decoded to two (the system downmix for more than two) and averaged. Asking AVAssetReader for one
/// channel from a stereo source gives an equal-power sum instead, (L + R) x 0.707 (`StereoChannelTests`), which raises
/// speech that is the same in both channels by 3 dB, above full scale for a source mastered within 3 dB of it.
public enum PCMDecoder {
    public static let analysisRate: Double = 44_100

    /// The number of channels the first format description of the track states (1 when it states none).
    static func channelCount(_ track: AVAssetTrack) async -> Int {
        guard let desc = try? await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return 1 }
        return max(1, Int(asbd.mChannelsPerFrame))
    }

    /// The average of the two channels of interleaved stereo samples.
    static func averageOfTwoChannels(_ interleaved: [Float]) -> [Float] {
        let n = interleaved.count / 2
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        var half: Float = 0.5
        interleaved.withUnsafeBufferPointer { p in
            out.withUnsafeMutableBufferPointer { o in
                vDSP_vasm(p.baseAddress!, 2, p.baseAddress! + 1, 2, &half, o.baseAddress!, 1, vDSP_Length(n))
            }
        }
        return out
    }

    public static func outputSettings(rate: Double, channels: Int = 1) -> [String: any Sendable] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
        ]
    }

    /// Decodes `[start, start + duration)` seconds (to the end when `duration` is nil), opening the file with its
    /// timing mode (ADR-0006 decision 2; precise unless the import proved the file a constant-bit-rate MP3).
    public static func decode(url: URL, start: Double, duration: Double?, rate: Double = analysisRate,
                              timing: AssetTiming = .precise) async throws -> DecodedPCM {
        try await decode(asset: timing.asset(url), start: start, duration: duration, rate: rate)
    }

    /// The same for an asset the caller opened (the G0.4 tests open some files without the precise key on purpose,
    /// to measure what estimated timing does in formats where the import never chooses it).
    public static func decode(asset: AVURLAsset, start: Double, duration: Double?, rate: Double = analysisRate) async throws -> DecodedPCM {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw PCMDecoderError.noAudioTrack }
        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw PCMDecoderError.cannotRead("\(error)") }
        let startTime = CMTime(seconds: start, preferredTimescale: 1_000_000)
        if let duration {
            reader.timeRange = CMTimeRange(start: startTime, duration: CMTime(seconds: duration, preferredTimescale: 1_000_000))
        } else if start > 0 {
            reader.timeRange = CMTimeRange(start: startTime, end: .positiveInfinity)
        }
        // Two or more channels are decoded to two and averaged; one channel is decoded as one (see the type).
        let channels = await channelCount(track) >= 2 ? 2 : 1
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings(rate: rate, channels: channels))
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw PCMDecoderError.cannotRead("cannot add output") }
        reader.add(output)
        guard reader.startReading() else { throw PCMDecoderError.cannotRead("\(String(describing: reader.error))") }

        let wanted = duration.map { Int(($0 * rate).rounded()) }
        var samples: [Float] = []
        if let wanted { samples.reserveCapacity(wanted) }
        var reportedStart: Double?
        while let buffer = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            var chunk = channels == 2 ? averageOfTwoChannels(floats(buffer)) : floats(buffer)
            if reportedStart == nil {
                // Trim samples the decoder delivered before the requested start (by its own timestamps).
                let early = Int(((start - pts) * rate).rounded())
                if early > 0 {
                    if early >= chunk.count { continue }
                    chunk.removeFirst(early)
                    reportedStart = pts + Double(early) / rate
                } else {
                    reportedStart = pts
                }
            }
            samples.append(contentsOf: chunk)
            if let wanted, samples.count >= wanted { break }
        }
        if reader.status == .failed { throw PCMDecoderError.readerFailed("\(String(describing: reader.error))") }
        reader.cancelReading()
        if let wanted, samples.count > wanted { samples.removeLast(samples.count - wanted) }
        return DecodedPCM(samples: samples, sampleRate: rate, reportedStart: reportedStart ?? start,
                          sourceFormat: await DecodedPCM.describe(track))
    }

    static func floats(_ buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        var out = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        out.withUnsafeMutableBytes { raw in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: raw.baseAddress!)
        }
        return out
    }
}
