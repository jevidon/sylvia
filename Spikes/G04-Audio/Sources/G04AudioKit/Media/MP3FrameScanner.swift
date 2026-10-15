import Foundation

/// Import-time proof that an MP3 file has a constant bit rate, for the per-file timing mode (ADR-0006 decision 2).
///
/// Without `AVURLAssetPreferPreciseDurationAndTimingKey`, AVFoundation places a position in an MP3 from the bit rate,
/// or from the table of contents of a Xing tag. That is exact when every frame has the same size in time and bytes
/// (constant bit rate) and seconds off in a variable-bit-rate file (G0.4: 0.56 s in a 10-minute VBR file with a Xing
/// tag, 14.1 s in a 10-hour one). So the importer may open a file with estimated timing only when it has proved the
/// stream constant. The proof is a walk over every MPEG audio frame header, from the first frame to the end of the
/// audio. The file is proved constant only when all of this holds:
/// - every frame is MPEG audio Layer III with the same MPEG version, sample rate, bit rate and channel count, and each
///   header sits exactly where the previous frame ends (no junk, no resynchronisation, no tag inside the audio);
/// - the audio ends exactly at the end of the file, or at a well-formed APEv2 and/or ID3v1 tag;
/// - the first frame carries LAME's `Info` tag or no tag at all. `Info` and `Xing` are the same structure (flags,
///   frame count, byte count, a 100-entry table of contents, LAME's extension with encoder delay and padding); LAME
///   names it `Info` for a constant-bit-rate stream and `Xing` for a variable- or average-bit-rate one. The name is a
///   claim, not proof (the frame walk is the proof), but a `Xing` or `VBRI` tag declares a variable bit rate and its
///   table of contents is what AVFoundation's estimated seeks follow, so a file with one is never treated as constant;
/// - when the `Info` tag states a frame count, it equals the frames walked (the count excludes the tag frame).
/// Anything else (a free-format or reserved field, a Layer I or II stream, a truncated last frame, unknown bytes before
/// or after the audio) leaves the file on precise timing: a file the scan cannot prove costs only speed, never
/// position. The walk reads one 4-byte header per frame, so it is linear in the number of frames.
public enum MP3FrameScanner {
    public enum Tag: String, Codable, Sendable {
        case info = "Info"
        case xing = "Xing"
        case vbri = "VBRI"
        case none
    }

    public enum Verdict: Equatable, Sendable {
        /// Every frame has the same bit rate, sample rate, MPEG version, layer and channel count, contiguously from the
        /// first frame to the end of the audio, with an `Info` tag (whose frame count matches) or none.
        case constantBitRate
        /// Not proved; the reason names what failed.
        case notProven(String)
    }

    public struct Scan: Equatable, Sendable {
        public var verdict: Verdict
        /// MPEG audio frames walked, a tag frame included.
        public var frames: Int = 0
        /// Bytes before the first frame (leading ID3v2 tags).
        public var firstFrameOffset: Int = 0
        /// "1", "2" or "2.5", from the first frame.
        public var version: String?
        public var layer: Int?
        public var sampleRate: Int?
        public var channels: Int?
        public var samplesPerFrame: Int?
        /// Frames per bit rate in kb/s.
        public var bitRates: [Int: Int] = [:]
        public var tag: Tag = .none
        /// The frame count the `Info` or `Xing` tag states (it does not count the tag frame).
        public var tagFrameCount: Int?
        /// Tags after the audio, in file order ("APEv2", "ID3v1").
        public var trailingTags: [String] = []

        public var isConstantBitRate: Bool { verdict == .constantBitRate }

        /// Frames that carry audio (the tag frame excluded).
        public var audioFrames: Int { max(0, frames - (tag == .none ? 0 : 1)) }

        /// The duration of one frame in milliseconds.
        public var frameDurationMs: Double? {
            guard let spf = samplesPerFrame, let sr = sampleRate, sr > 0 else { return nil }
            return Double(spf) * 1000 / Double(sr)
        }

        /// The audio frames' duration (before any encoder delay or padding is trimmed), in milliseconds.
        public var audioDurationMs: Int64? {
            guard let f = frameDurationMs, frames > 0 else { return nil }
            return Int64((Double(audioFrames) * f).rounded())
        }

        /// The bit rates in kb/s, ascending.
        public var bitRateList: [Int] { bitRates.keys.sorted() }

        public var reason: String {
            switch verdict {
            case .constantBitRate: "constant bit rate"
            case let .notProven(r): r
            }
        }
    }

    /// Scans the file at `url` (memory-mapped; only the frame headers are read).
    public static func scan(url: URL) throws -> Scan {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return scan(data)
    }

    public static func scan(_ data: Data) -> Scan {
        data.withUnsafeBytes { scan(bytes: $0) }
    }

    // MARK: Internals

    /// One MPEG audio frame header (ISO/IEC 11172-3 and 13818-3).
    struct Header: Equatable {
        /// 3 = MPEG-1, 2 = MPEG-2, 0 = MPEG-2.5 (the two version bits).
        var versionBits: UInt32
        var layer: Int
        var protected: Bool
        var bitRateIndex: Int
        var sampleRate: Int
        var padding: Int
        var channelMode: Int

        var version: String { versionBits == 3 ? "1" : versionBits == 2 ? "2" : "2.5" }
        var channels: Int { channelMode == 3 ? 1 : 2 }
        var isMPEG1: Bool { versionBits == 3 }
        var samplesPerFrame: Int {
            switch layer {
            case 1: 384
            case 2: 1152
            default: isMPEG1 ? 1152 : 576
            }
        }

        static let layer3MPEG1: [Int] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        static let layer3MPEG2: [Int] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

        /// kb/s for Layer III; nil for the free format (index 0) or another layer.
        var bitRateKbps: Int? {
            guard layer == 3, bitRateIndex > 0 else { return nil }
            return (isMPEG1 ? Self.layer3MPEG1 : Self.layer3MPEG2)[bitRateIndex]
        }

        /// Frame length in bytes (Layer III with a bit rate).
        var length: Int? {
            guard let kbps = bitRateKbps else { return nil }
            return (isMPEG1 ? 144_000 : 72_000) * kbps / sampleRate + padding
        }

        /// Where a Xing or Info tag starts in the first frame: after the header, the CRC if present and the side
        /// information.
        var xingOffset: Int {
            let side = isMPEG1 ? (channels == 1 ? 17 : 32) : (channels == 1 ? 9 : 17)
            return 4 + (protected ? 2 : 0) + side
        }

        init?(_ h: UInt32) {
            guard h & 0xFFE0_0000 == 0xFFE0_0000 else { return nil }  // 11 sync bits
            let v = (h >> 19) & 3
            guard v != 1 else { return nil }  // reserved version
            let l = (h >> 17) & 3
            guard l != 0 else { return nil }  // reserved layer
            let bri = Int((h >> 12) & 0xF)
            guard bri != 15 else { return nil }  // "bad" bit rate
            let sri = Int((h >> 10) & 3)
            guard sri != 3 else { return nil }  // reserved sample rate
            guard h & 3 != 2 else { return nil }  // reserved emphasis
            let rates: [Int] = v == 3 ? [44_100, 48_000, 32_000] : v == 2 ? [22_050, 24_000, 16_000] : [11_025, 12_000, 8_000]
            versionBits = v
            layer = 4 - Int(l)
            protected = (h >> 16) & 1 == 0
            bitRateIndex = bri
            sampleRate = rates[sri]
            padding = Int((h >> 9) & 1)
            channelMode = Int((h >> 6) & 3)
        }
    }

    static func scan(bytes b: UnsafeRawBufferPointer) -> Scan {
        var s = Scan(verdict: .notProven("no MPEG audio frames"))
        let n = b.count
        func be32(_ i: Int) -> UInt32 {
            UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
        }
        func le32(_ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
        func ascii(_ i: Int, _ text: String) -> Bool {
            let bytes = Array(text.utf8)
            guard i >= 0, i + bytes.count <= n else { return false }
            for (k, c) in bytes.enumerated() where b[i + k] != c { return false }
            return true
        }

        // Leading ID3v2 tags (one or more): "ID3", version, revision, flags, then a 28-bit syncsafe size; a footer
        // (flag 0x10) adds 10 bytes.
        var pos = 0
        while ascii(pos, "ID3") {
            guard pos + 10 <= n, b[pos + 3] != 0xFF, b[pos + 4] != 0xFF,
                  (b[pos + 6] | b[pos + 7] | b[pos + 8] | b[pos + 9]) & 0x80 == 0 else {
                s.verdict = .notProven("malformed ID3v2 tag at byte \(pos)")
                return s
            }
            let size = Int(b[pos + 6]) << 21 | Int(b[pos + 7]) << 14 | Int(b[pos + 8]) << 7 | Int(b[pos + 9])
            let next = pos + 10 + size + (b[pos + 5] & 0x10 != 0 ? 10 : 0)
            guard next <= n else {
                s.verdict = .notProven("the ID3v2 tag at byte \(pos) runs past the end of the file")
                return s
            }
            pos = next
        }
        s.firstFrameOffset = pos

        // Tags after the audio: ID3v1 is the last 128 bytes ("TAG"); an APEv2 tag ends with a 32-byte footer
        // ("APETAGEX", version, size including the footer, item count, flags) and may have a header (flag bit 31).
        var end = n
        var trailing: [String] = []
        if end - pos >= 128, ascii(end - 128, "TAG") {
            trailing.insert("ID3v1", at: 0)
            end -= 128
        }
        if end - pos >= 32, ascii(end - 32, "APETAGEX") {
            let size = Int(le32(end - 20)), flags = le32(end - 12)
            let total = size + (flags & 0x8000_0000 != 0 ? 32 : 0)
            guard size >= 32, total <= end - pos else {
                s.verdict = .notProven("malformed APEv2 tag")
                return s
            }
            trailing.insert("APEv2", at: 0)
            end -= total
        }
        s.trailingTags = trailing

        // Walk the frames. A structural problem stops the walk; different bit rates do not (they are counted).
        var first: Header?
        var problem: String?
        while pos < end {
            guard end - pos >= 4 else {
                problem = "\(end - pos) bytes after the last frame"
                break
            }
            guard let h = Header(be32(pos)) else {
                problem = ascii(pos, "ID3") ? "an ID3 tag inside the audio at byte \(pos)"
                    : s.frames == 0 ? "no frame header where the audio starts (byte \(pos))"
                    : "no frame header at byte \(pos) (after frame \(s.frames))"
                break
            }
            if let f = first {
                if h.versionBits != f.versionBits || h.layer != f.layer {
                    problem = "the MPEG version or layer changes at frame \(s.frames)"
                    break
                }
                if h.sampleRate != f.sampleRate {
                    problem = "the sample rate changes at frame \(s.frames) (\(f.sampleRate) to \(h.sampleRate) Hz)"
                    break
                }
                if h.channels != f.channels {
                    problem = "the channel count changes at frame \(s.frames)"
                    break
                }
            } else {
                first = h
                s.version = h.version
                s.layer = h.layer
                s.sampleRate = h.sampleRate
                s.channels = h.channels
                s.samplesPerFrame = h.samplesPerFrame
                guard h.layer == 3 else {
                    problem = "MPEG Layer \(h.layer), not Layer III"
                    break
                }
            }
            guard let kbps = h.bitRateKbps, let length = h.length else {
                problem = "free-format bit rate at frame \(s.frames)"
                break
            }
            guard pos + length <= end else {
                problem = "the last frame is truncated (\(end - pos) of \(length) bytes)"
                break
            }
            if s.frames == 0 {
                // A Xing or Info tag sits in the first frame after the side information; VBRI 32 bytes after the header.
                let x = pos + h.xingOffset
                if x + 8 <= pos + length, ascii(x, "Xing") || ascii(x, "Info") {
                    s.tag = ascii(x, "Xing") ? .xing : .info
                    if be32(x + 4) & 1 != 0, x + 12 <= pos + length { s.tagFrameCount = Int(be32(x + 8)) }
                } else if pos + 40 <= pos + length, ascii(pos + 36, "VBRI") {
                    s.tag = .vbri
                }
            }
            s.bitRates[kbps, default: 0] += 1
            s.frames += 1
            pos += length
        }

        var reasons: [String] = []
        if let problem { reasons.append(problem) }
        if s.frames == 0, problem == nil { reasons.append("no MPEG audio frames") }
        if s.bitRates.count > 1 {
            let list = s.bitRateList
            reasons.append("variable bit rate: \(list.count) bit rates (\(list.first ?? 0)-\(list.last ?? 0) kb/s)")
        }
        switch s.tag {
        case .xing: reasons.append("a Xing tag (declares a variable bit rate; its table of contents drives estimated seeks)")
        case .vbri: reasons.append("a VBRI tag (declares a variable bit rate)")
        case .info:
            if let count = s.tagFrameCount, problem == nil, count != s.frames - 1 {
                reasons.append("the Info tag counts \(count) frames, the scan \(s.frames - 1)")
            }
        case .none: break
        }
        s.verdict = reasons.isEmpty ? .constantBitRate : .notProven(reasons.joined(separator: "; "))
        return s
    }
}
