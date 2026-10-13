import AVFoundation
import Foundation

/// One file-local piece of an excerpt, the file that holds it and how to open that file (its member's timing mode).
public struct SourceSegment: Sendable {
    public var url: URL
    public var range: AudioRange
    public var timing: AssetTiming
    public init(url: URL, range: AudioRange, timing: AssetTiming = .precise) {
        self.url = url
        self.range = range
        self.timing = timing
    }
}

/// The retained excerpt and the timing that was actually exported (plan 10.2: "include actual exported timing").
public struct ExportedExcerpt: Codable, Hashable, Sendable {
    public var fileName: String
    /// The excerpt's own format (`m4a/aac-lc/64k/44.1k/mono`).
    public var format: String
    /// The source format of each range, in order (`codec/sample rate/channels` of the source track, for example
    /// `.mp3/44100/1`). The measured offset between `actualRanges` and the true content position depends on the
    /// source codec (ADR-0006), so a per-codec correction can be applied to stored captures later.
    public var sourceFormats: [String]
    public var requestedRanges: [AudioRange]
    /// Ranges as the decoder's timestamps place the exported samples. The G0.4 timing tests measure how far these
    /// claims are from the true source position per codec.
    public var actualRanges: [AudioRange]
    public var frameCount: Int
    public var sampleRate: Double
    /// Duration of the written file as AVFoundation reports it when reopened (encoder priming and padding applied).
    public var outputDurationMs: Int64?
    public var byteCount: Int64
}

public enum ExportError: Error, Equatable, Sendable {
    case noSegments
    case tooLong(ms: Int64)
    case decodeFailed(String)
    case encodeFailed(String)
    case emptyOutput
}

public protocol ExcerptExporting: Sendable {
    func export(_ segments: [SourceSegment], to url: URL) async throws -> ExportedExcerpt
}

/// Decodes each source range with AVAssetReader (sample-accurate trim by presentation timestamp), concatenates the
/// ranges in order, and encodes AAC-LC 64 kb/s mono 44.1 kHz into an .m4a through AVAudioFile (ExtAudioFile).
/// The file is written under a temporary name, given its protection class, synced and renamed, so a crash never
/// leaves a half excerpt that looks complete. Memory is bounded by the 120-second excerpt limit (about 21 MB of
/// Float32 at most).
public struct AACExcerptExporter: ExcerptExporting {
    public static let maximumMs: Int64 = 120_000
    public static let format = "m4a/aac-lc/64k/44.1k/mono"
    public var rate: Double = 44_100
    public var bitRate = 64_000
    /// The excerpt's protection class: class C like every store on the capture path, set explicitly on the file and
    /// its directory rather than left to the platform default (ADR-0007 decision 4, ADR-0012; review R5-04).
    public var protection: FileProtectionType = DurableFile.lockedCaptureProtection
    /// How the class is applied to the finished temporary file before it is renamed into place (tests observe it).
    public var applyProtection: @Sendable (FileProtectionType, URL) throws -> Void = { try DurableFile.applyProtection($0, to: $1) }

    public init() {}

    public func export(_ segments: [SourceSegment], to url: URL) async throws -> ExportedExcerpt {
        guard !segments.isEmpty else { throw ExportError.noSegments }
        let total = segments.reduce(0) { $0 + $1.range.durationMs }
        guard total <= Self.maximumMs else { throw ExportError.tooLong(ms: total) }

        var pieces: [(samples: [Float], actual: AudioRange, sourceFormat: String)] = []
        for segment in segments {
            let r = segment.range
            let decoded: DecodedPCM
            do {
                decoded = try await PCMDecoder.decode(url: segment.url, start: Double(r.startMs) / 1000,
                                                      duration: Double(r.durationMs) / 1000, rate: rate, timing: segment.timing)
            } catch {
                throw ExportError.decodeFailed("\(segment.url.lastPathComponent): \(error)")
            }
            let startMs = Int64((decoded.reportedStart * 1000).rounded())
            let endMs = startMs + Int64((Double(decoded.samples.count) / rate * 1000).rounded())
            pieces.append((decoded.samples, AudioRange(assetID: r.assetID, startMs: startMs, endMs: endMs), decoded.sourceFormat))
        }
        let frames = pieces.reduce(0) { $0 + $1.samples.count }
        guard frames > 0 else { throw ExportError.emptyOutput }

        let fm = FileManager.default
        try DurableFile.createDirectory(url.deletingLastPathComponent(), protection: protection)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString).m4a")
        defer { try? fm.removeItem(at: temp) }
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: rate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: bitRate,
            ]
            let file = try AVAudioFile(forWriting: temp, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let format = file.processingFormat
            let chunk = 32_768
            for piece in pieces {
                var offset = 0
                while offset < piece.samples.count {
                    let n = min(chunk, piece.samples.count - offset)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else {
                        throw ExportError.encodeFailed("buffer allocation")
                    }
                    buffer.frameLength = AVAudioFrameCount(n)
                    piece.samples.withUnsafeBufferPointer { src in
                        buffer.floatChannelData![0].update(from: src.baseAddress! + offset, count: n)
                    }
                    try file.write(from: buffer)
                    offset += n
                }
            }
            file.close()
        } catch let e as ExportError {
            throw e
        } catch {
            throw ExportError.encodeFailed("\(error)")
        }
        do {
            try applyProtection(protection, temp)
        } catch {
            throw ExportError.encodeFailed("file protection: \(error)")
        }
        try DurableFile.sync(temp)
        // rename(2) replaces an earlier excerpt atomically: a crash leaves either the old file or the new one.
        guard rename(temp.path, url.path) == 0 else { throw ExportError.encodeFailed("rename failed, errno \(errno)") }
        try DurableFile.syncDirectory(url.deletingLastPathComponent())

        let outputDuration = try? await AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]).load(.duration)
        let bytes = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ExportedExcerpt(fileName: url.lastPathComponent, format: Self.format, sourceFormats: pieces.map(\.sourceFormat),
                               requestedRanges: segments.map(\.range), actualRanges: pieces.map(\.actual),
                               frameCount: frames, sampleRate: rate,
                               outputDurationMs: outputDuration.flatMap(AssetInspector.milliseconds), byteCount: bytes)
    }
}
