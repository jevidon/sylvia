import AVFoundation
import Foundation

/// What AVFoundation reports about a file before playback (plan 8.3 "validate both container and codec").
public struct AssetReport: Sendable {
    public enum ChapterSource: String, Sendable { case avFoundation, id3Chap, none }
    public var isPlayable: Bool
    public var audioTrackCount: Int
    /// Duration with `AVURLAssetPreferPreciseDurationAndTimingKey`. Nil when the asset reports an indefinite or
    /// invalid duration.
    public var preciseDurationMs: Int64?
    /// Duration without the precise-timing option (what a quick inspection would show).
    public var estimatedDurationMs: Int64?
    public var codec: String?
    public var sampleRate: Double?
    public var channels: Int?
    public var chapters: [ChapterInfo]
    public var chapterSource: ChapterSource
    /// Chapters whose end AVFoundation reported as indefinite and that were closed at the duration.
    public var chapterEndsClosedAtDuration: Int
    public var trackNumber: Int?
    public var trackTotal: Int?
    public var discNumber: Int?
    /// The per-file timing mode the import chooses (ADR-0006 decision 2): estimated only for an MP3 the frame scan
    /// proves constant bit rate, precise otherwise.
    public var timingDecision: TimingDecision
    public var timing: AssetTiming { timingDecision.timing }
    /// The whole inspection, the MP3 frame scan included.
    public var inspectSeconds: Double
}

public enum AssetInspector {
    public static func preciseAsset(_ url: URL) -> AVURLAsset { AssetTiming.precise.asset(url) }

    public static func inspect(_ url: URL) async throws -> AssetReport {
        let started = Date()
        let asset = preciseAsset(url)
        let (playable, duration) = try await asset.load(.isPlayable, .duration)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        var codec: String?
        var sampleRate: Double?
        var channels: Int?
        if let track = tracks.first, let desc = try await track.load(.formatDescriptions).first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
            codec = fourCC(asbd.mFormatID)
            sampleRate = asbd.mSampleRate
            channels = Int(asbd.mChannelsPerFrame)
        }
        let estimated = try? await AVURLAsset(url: url).load(.duration)

        let read = try await avChapterList(asset, durationMs: milliseconds(duration))
        var chapters = read.chapters
        var closed = read.closedAtDuration
        var source: AssetReport.ChapterSource = chapters.isEmpty ? .none : .avFoundation
        if chapters.isEmpty, let id3 = try? ID3Chapters.read(url: url), !id3.isEmpty {
            chapters = id3
            closed = 0
            source = .id3Chap
        }
        let numbers = try await trackNumbers(asset)
        // The per-file timing mode (ADR-0006 decision 2): an MP3 is walked frame by frame (linear in its size; the
        // scan time per file is in mp3-cbr-detection.tsv) to prove it constant bit rate.
        var scan: MP3FrameScanner.Scan?
        var scanSeconds: Double?
        if codec == ".mp3" {
            let t0 = ProcessInfo.processInfo.systemUptime
            scan = try? MP3FrameScanner.scan(url: url)
            scanSeconds = ProcessInfo.processInfo.systemUptime - t0
        }
        let decision = TimingDecision.decide(codec: codec, scan: scan, scanSeconds: scanSeconds, preciseDurationMs: milliseconds(duration))
        return AssetReport(
            isPlayable: playable, audioTrackCount: tracks.count,
            preciseDurationMs: milliseconds(duration), estimatedDurationMs: estimated.flatMap(milliseconds),
            codec: codec, sampleRate: sampleRate, channels: channels,
            chapters: chapters, chapterSource: source, chapterEndsClosedAtDuration: closed,
            trackNumber: numbers.track, trackTotal: numbers.total, discNumber: numbers.disc,
            timingDecision: decision, inspectSeconds: Date().timeIntervalSince(started))
    }

    public static func milliseconds(_ t: CMTime) -> Int64? {
        guard t.isValid, t.isNumeric, !t.isIndefinite else { return nil }
        return Int64((t.seconds * 1000).rounded())
    }

    /// `durationMs` closes a chapter whose end AVFoundation reports as indefinite: for chapters read from Vorbis
    /// comments (FLAC, Ogg) the last chapter's time range has no end (seen in G0.4). A chapter with no usable start is
    /// skipped.
    static func avChapters(_ asset: AVAsset, durationMs: Int64?) async throws -> [ChapterInfo] {
        try await avChapterList(asset, durationMs: durationMs).chapters
    }

    static func avChapterList(_ asset: AVAsset, durationMs: Int64?) async throws -> (chapters: [ChapterInfo], closedAtDuration: Int) {
        // Chapter tracks are often tagged "und"; matching a preferred language list would return nothing for them,
        // so ask for the first locale the asset declares.
        let locales = try await asset.load(.availableChapterLocales)
        guard let locale = locales.first else { return ([], 0) }
        let groups = try await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
        var result: [ChapterInfo] = []
        var closed = 0
        for (i, group) in groups.enumerated() {
            let titleItem = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first
            let title = (try? await titleItem?.load(.stringValue)) ?? nil
            let r = group.timeRange
            guard let s = milliseconds(r.start) else { continue }
            let end: Int64
            if let e = milliseconds(r.end) {
                end = e
            } else if let d = durationMs {
                end = d
                closed += 1
            } else { continue }
            guard end > s else { continue }
            result.append(ChapterInfo(title: title ?? "Chapter \(i + 1)", startMs: s, endMs: end))
        }
        return (result, closed)
    }

    static func trackNumbers(_ asset: AVAsset) async throws -> (track: Int?, total: Int?, disc: Int?) {
        let items = try await asset.load(.metadata)
        var track: Int?, total: Int?, disc: Int?
        for item in items {
            guard let id = item.identifier else { continue }
            switch id {
            case .id3MetadataTrackNumber:
                if let s = try await item.load(.stringValue) { (track, total) = parseSlashPair(s) }
            case .id3MetadataPartOfASet:
                if let s = try await item.load(.stringValue) { disc = parseSlashPair(s).0 }
            case .iTunesMetadataTrackNumber:
                if let d = try await item.load(.dataValue), d.count >= 6 {
                    let b = [UInt8](d)
                    track = Int(b[2]) << 8 | Int(b[3])
                    let t = Int(b[4]) << 8 | Int(b[5])
                    total = t > 0 ? t : nil
                }
            case .iTunesMetadataDiscNumber:
                if let d = try await item.load(.dataValue), d.count >= 4 {
                    let b = [UInt8](d)
                    disc = Int(b[2]) << 8 | Int(b[3])
                }
            default:
                continue
            }
        }
        return (track, total, disc)
    }

    static func parseSlashPair(_ s: String) -> (Int?, Int?) {
        let parts = s.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return (parts.first.flatMap { Int($0) }, parts.count > 1 ? Int(parts[1]) : nil)
    }

    public static func fourCC(_ v: FourCharCode) -> String {
        let bytes = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) { return String(bytes: bytes, encoding: .ascii) ?? "\(v)" }
        return "\(v)"
    }
}
