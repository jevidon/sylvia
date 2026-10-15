import AVFoundation
import Foundation

/// Mitigation candidate for slow opening and slow first seeks (review R3-01; ADR-0006): with precise timing,
/// AVFoundation scans a native FLAC or Ogg file (and an MP3 without a Xing/VBRI header) when an AVPlayerItem opens it,
/// in proportion to the file's length, and a first seek into an MP3 costs time proportional to its depth, while an
/// MPEG-4 or CAF file opens and seeks from its packet table at once. This copies the audio track's compressed packets
/// unchanged (no decode, no re-encode) into such a container at import, so every later launch opens the copy. Stage 0
/// evidence code: the tests measure the remux time, the copy's open and resume times and its content against the
/// source and the masters. Whether the product keeps the original, the copy or both, and how anchors keep naming the
/// original asset (they are file-local milliseconds of the same audio), is an ADR-0006 decision. Chapters are not
/// copied (the importer keeps the chapters it read from the original).
public enum ImportRemuxer {
    /// MPEG-4 audio (.m4a) takes FLAC, Opus and AAC packets; AVAssetWriter refuses MP3 packets in MPEG-4 (`canAdd` is
    /// false for .m4a and .mp4 on the simulator: ContainerProbeTests, container-probes.txt), so MP3 goes into CAF
    /// (.caf), which takes them.
    public enum Container: String, Sendable {
        case mpeg4, caf
        var fileType: AVFileType { self == .mpeg4 ? .m4a : .caf }
        public var fileExtension: String { self == .mpeg4 ? "m4a" : "caf" }
    }

    public struct Result: Sendable {
        public var seconds: Double
        public var bytes: Int64
        public var sampleBuffers: Int
        public var sourceFormat: String
    }

    public enum RemuxError: Error, Sendable {
        case noAudioTrack
        case cannotRemux(String)
    }

    /// Remuxes the first audio track of `source` into `container` at `destination` (temporary file, sync, rename). The
    /// source is read sequentially without the precise-timing option: sequential reading delivers every packet with
    /// its own timestamp, and the precise option would only add the slow scan this avoids. The tests check the copy's
    /// duration and content against the source and the masters.
    public static func remux(_ source: URL, to destination: URL, container: Container) async throws -> Result {
        let started = ProcessInfo.processInfo.systemUptime
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw RemuxError.noAudioTrack }
        guard let format = try await track.load(.formatDescriptions).first else { throw RemuxError.cannotRemux("no format description") }
        let sourceFormat = await DecodedPCM.describe(track)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = destination.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString).\(container.fileExtension)")
        defer { try? fm.removeItem(at: temp) }

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)  // compressed packets, as stored
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw RemuxError.cannotRemux("reader output") }
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: temp, fileType: container.fileType)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw RemuxError.cannotRemux("the \(container.rawValue) writer does not take \(sourceFormat) packets") }
        writer.add(input)
        guard reader.startReading() else { throw RemuxError.cannotRemux("reader: \(String(describing: reader.error))") }
        guard writer.startWriting() else { throw RemuxError.cannotRemux("writer: \(String(describing: writer.error))") }
        writer.startSession(atSourceTime: .zero)
        var buffers = 0
        while let buffer = output.copyNextSampleBuffer() {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw RemuxError.cannotRemux("writer: \(String(describing: writer.error))") }
                try await Task.sleep(for: .milliseconds(1))
            }
            guard input.append(buffer) else { throw RemuxError.cannotRemux("append: \(String(describing: writer.error))") }
            buffers += 1
        }
        if reader.status == .failed { throw RemuxError.cannotRemux("reader: \(String(describing: reader.error))") }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw RemuxError.cannotRemux("finish: \(String(describing: writer.error))") }
        try DurableFile.sync(temp)
        guard rename(temp.path, destination.path) == 0 else { throw RemuxError.cannotRemux("rename failed, errno \(errno)") }
        try DurableFile.syncDirectory(destination.deletingLastPathComponent())
        let bytes = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        return Result(seconds: ProcessInfo.processInfo.systemUptime - started, bytes: bytes, sampleBuffers: buffers, sourceFormat: sourceFormat)
    }
}
