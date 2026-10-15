import AVFoundation
import Foundation

/// How the player, the preview and the excerpt export open one imported file (ADR-0006 decision 2, the per-file timing
/// mode). Decided once, at import, from what the file is; stored with the member (`EditionMember.timing`).
public enum AssetTiming: String, Codable, Sendable, CaseIterable {
    /// With `AVURLAssetPreferPreciseDurationAndTimingKey`: exact positions in every format. With it AVFoundation scans a
    /// native FLAC, Ogg Opus or header-less MP3 file when it opens it (time proportional to the file's length), and the
    /// first seek into an MP3 costs time proportional to its depth (G0.4 report rows 21 and 33).
    case precise
    /// Without the precise key, for an MP3 the import proved constant bit rate (`MP3FrameScanner`): AVFoundation then
    /// computes positions from the bit rate, which is exact for such a file, and opens and seeks at once at any depth.
    /// Never chosen for any other file: estimated timing lands seconds off in VBR MP3, FLAC and Ogg Opus.
    case estimatedCBR

    /// The asset the player, preview and export open for a file with this timing.
    public func asset(_ url: URL) -> AVURLAsset {
        switch self {
        case .precise: AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        case .estimatedCBR: AVURLAsset(url: url)
        }
    }
}

/// The import's timing decision for one file and why (recorded with the member; the G0.4 tables print it).
public struct TimingDecision: Equatable, Sendable {
    public var timing: AssetTiming
    public var reason: String
    /// The MP3 frame scan, for MP3 files.
    public var scan: MP3FrameScanner.Scan?
    /// Wall time of the scan, in seconds.
    public var scanSeconds: Double?

    /// `codec`: the track's format ID as `AssetInspector.fourCC` prints it (".mp3" for MPEG audio Layer III).
    /// `preciseDurationMs`: AVFoundation's duration with precise timing. Estimated timing is chosen only when the scan
    /// proves a constant bit rate and the scanned audio duration agrees with AVFoundation's within three frames (encoder
    /// delay and padding, which LAME's tag lets AVFoundation trim, are under two frames), so a file whose frames the scan
    /// and AVFoundation count differently stays precise.
    public static func decide(codec: String?, scan: MP3FrameScanner.Scan?, scanSeconds: Double? = nil,
                              preciseDurationMs: Int64?) -> TimingDecision {
        guard codec == ".mp3" else {
            return TimingDecision(timing: .precise, reason: "not MP3", scan: nil, scanSeconds: nil)
        }
        guard let scan else {
            return TimingDecision(timing: .precise, reason: "the frame scan could not read the file", scan: nil, scanSeconds: scanSeconds)
        }
        guard scan.isConstantBitRate else {
            return TimingDecision(timing: .precise, reason: scan.reason, scan: scan, scanSeconds: scanSeconds)
        }
        guard let precise = preciseDurationMs, let scanned = scan.audioDurationMs, let frame = scan.frameDurationMs,
              Double(abs(precise - scanned)) <= 3 * frame else {
            let detail = "the scanned audio (\(scan.audioDurationMs.map(String.init) ?? "-") ms) and AVFoundation's precise duration (\(preciseDurationMs.map(String.init) ?? "-") ms) differ by more than three frames"
            return TimingDecision(timing: .precise, reason: detail, scan: scan, scanSeconds: scanSeconds)
        }
        let kbps = scan.bitRateList.first ?? 0
        let tag = scan.tag == .info ? "Info tag" : "no tag"
        return TimingDecision(timing: .estimatedCBR,
                              reason: "constant bit rate \(kbps) kb/s, \(scan.frames) frames, \(tag)",
                              scan: scan, scanSeconds: scanSeconds)
    }
}
