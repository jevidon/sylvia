import Foundation
import Testing
@testable import G04AudioKit

/// Synthetic MPEG audio Layer III streams: valid frame headers with silent (zero) payloads, padded as encoders pad a
/// constant-bit-rate stream, with optional tags.
enum SyntheticMP3 {
    enum Version { case mpeg1, mpeg2 }

    static func header(_ version: Version = .mpeg1, kbps: Int, sampleRate: Int, padding: Bool, mono: Bool = true,
                       freeFormat: Bool = false, layer: Int = 3) -> UInt32 {
        let table = version == .mpeg1 ? MP3FrameScanner.Header.layer3MPEG1 : MP3FrameScanner.Header.layer3MPEG2
        let bri = freeFormat ? 0 : UInt32(table.firstIndex(of: kbps)!)
        let rates = version == .mpeg1 ? [44_100, 48_000, 32_000] : [22_050, 24_000, 16_000]
        let sri = UInt32(rates.firstIndex(of: sampleRate)!)
        let v: UInt32 = version == .mpeg1 ? 3 : 2
        let l = UInt32(4 - layer)
        return 0xFFE0_0000 | v << 19 | l << 17 | 1 << 16 | bri << 12 | sri << 10 | (padding ? 1 : 0) << 9 | (mono ? 3 : 0) << 6
    }

    static func bytes(_ x: UInt32) -> [UInt8] { [UInt8(x >> 24), UInt8(x >> 16 & 0xFF), UInt8(x >> 8 & 0xFF), UInt8(x & 0xFF)] }

    /// `frames` frames (a tag frame included when `tag` is set) at `kbps`, except the frames listed in `kbpsAt`.
    /// Returns the bytes and the offset of each frame.
    static func stream(frames: Int, kbps: Int = 64, sampleRate: Int = 44_100, version: Version = .mpeg1, mono: Bool = true,
                       tag: MP3FrameScanner.Tag = .none, tagFrameCount: Int? = nil, kbpsAt: [Int: Int] = [:],
                       sampleRateAt: [Int: Int] = [:], monoAt: [Int: Bool] = [:]) -> (data: [UInt8], offsets: [Int]) {
        var out: [UInt8] = []
        var offsets: [Int] = []
        var rest = 0
        for i in 0..<frames {
            let k = kbpsAt[i] ?? kbps
            let sr = sampleRateAt[i] ?? sampleRate
            let m = monoAt[i] ?? mono
            let numerator = (version == .mpeg1 ? 144_000 : 72_000) * k
            rest += numerator % sr
            let pad = rest >= sr
            if pad { rest -= sr }
            let length = numerator / sr + (pad ? 1 : 0)
            var frame = [UInt8](repeating: 0, count: length)
            frame.replaceSubrange(0..<4, with: bytes(header(version, kbps: k, sampleRate: sr, padding: pad, mono: m)))
            if i == 0, tag != .none {
                let at: Int
                if tag == .vbri {
                    at = 36
                } else {
                    let side = version == .mpeg1 ? (m ? 17 : 32) : (m ? 9 : 17)
                    at = 4 + side
                }
                frame.replaceSubrange(at..<at + 4, with: Array(tag.rawValue.utf8))
                if tag != .vbri {
                    frame.replaceSubrange(at + 4..<at + 8, with: bytes(0x0000_0001))  // flags: frame count present
                    frame.replaceSubrange(at + 8..<at + 12, with: bytes(UInt32(tagFrameCount ?? frames - 1)))
                }
            }
            offsets.append(out.count)
            out += frame
        }
        return (out, offsets)
    }

    static func id3v2(payload: Int, footer: Bool = false) -> [UInt8] {
        let size = payload
        let syncsafe: [UInt8] = [UInt8(size >> 21 & 0x7F), UInt8(size >> 14 & 0x7F), UInt8(size >> 7 & 0x7F), UInt8(size & 0x7F)]
        var tag: [UInt8] = Array("ID3".utf8) + [4, 0, footer ? 0x10 : 0] + syncsafe + [UInt8](repeating: 0x20, count: payload)
        if footer { tag += Array("3DI".utf8) + [4, 0, 0x10] + syncsafe }
        return tag
    }

    static var id3v1: [UInt8] { Array("TAG".utf8) + [UInt8](repeating: 0x20, count: 125) }

    /// An APEv2 tag with a header and one item.
    static var apev2: [UInt8] {
        func le(_ x: UInt32) -> [UInt8] { [UInt8(x & 0xFF), UInt8(x >> 8 & 0xFF), UInt8(x >> 16 & 0xFF), UInt8(x >> 24)] }
        let item: [UInt8] = le(5) + le(0) + Array("Title".utf8) + [0] + Array("Hello".utf8)
        let size = UInt32(item.count + 32)  // items and footer
        let header = Array("APETAGEX".utf8) + le(2000) + le(size) + le(1) + le(0xA000_0000) + [UInt8](repeating: 0, count: 8)
        let footer = Array("APETAGEX".utf8) + le(2000) + le(size) + le(1) + le(0x8000_0000) + [UInt8](repeating: 0, count: 8)
        return header + item + footer
    }
}

/// The import's constant-bit-rate proof (ADR-0006 decision 2; review R4-01) on synthetic streams. The fixtures (real
/// encodes, the LibriVox files, the 10-hour files) are classified in `PerFileTimingTests` (serialized: they read up
/// to 300 MB per file).
@Suite("MP3 frame scan: constant-bit-rate proof (unit, synthetic streams)")
struct MP3FrameScannerTests {
    func scan(_ bytes: [UInt8]) -> MP3FrameScanner.Scan { MP3FrameScanner.scan(Data(bytes)) }

    @Test func constantStreamsWithAnInfoTagOrNoTagAreProved() {
        let info = SyntheticMP3.stream(frames: 500, tag: .info)
        let a = scan(info.data)
        #expect(a.verdict == .constantBitRate, "\(a.reason)")
        #expect(a.frames == 500 && a.audioFrames == 499 && a.tag == .info && a.tagFrameCount == 499)
        #expect(a.bitRates == [64: 500] && a.sampleRate == 44_100 && a.channels == 1 && a.version == "1" && a.samplesPerFrame == 1152)
        #expect(a.audioDurationMs == Int64((499.0 * 1152 / 44_100 * 1000).rounded()))
        // Padding: frames of 208 and 209 bytes, as a 64 kb/s stream at 44.1 kHz has.
        let lengths = Set(zip(info.offsets, info.offsets.dropFirst()).map { $1 - $0 })
        #expect(lengths == [208, 209])

        let none = scan(SyntheticMP3.stream(frames: 500).data)
        #expect(none.verdict == .constantBitRate && none.tag == .none && none.audioFrames == 500)

        // MPEG-2 at 22.05 kHz, stereo (the LibriVox section files are MPEG-2 mono).
        let mpeg2 = scan(SyntheticMP3.stream(frames: 300, kbps: 64, sampleRate: 22_050, version: .mpeg2, mono: false, tag: .info).data)
        #expect(mpeg2.verdict == .constantBitRate, "\(mpeg2.reason)")
        #expect(mpeg2.version == "2" && mpeg2.samplesPerFrame == 576 && mpeg2.channels == 2)
    }

    @Test func tagsBeforeAndAfterTheAudioAreSkipped() {
        let body = SyntheticMP3.stream(frames: 200, tag: .info).data
        let s = scan(SyntheticMP3.id3v2(payload: 300) + SyntheticMP3.id3v2(payload: 40, footer: true) + body + SyntheticMP3.apev2 + SyntheticMP3.id3v1)
        #expect(s.verdict == .constantBitRate, "\(s.reason)")
        #expect(s.firstFrameOffset == 310 + 60)
        #expect(s.trailingTags == ["APEv2", "ID3v1"])
        #expect(s.frames == 200)
    }

    @Test func oneFrameAtAnotherBitRateIsNotProved() {
        let s = scan(SyntheticMP3.stream(frames: 400, tag: .info, kbpsAt: [250: 56]).data)
        #expect(!s.isConstantBitRate)
        #expect(s.bitRates == [64: 399, 56: 1])
        #expect(s.reason.contains("variable bit rate: 2 bit rates (56-64 kb/s)"), "\(s.reason)")
    }

    /// `Info` and `Xing` are the same structure; the name is LAME's claim (`Info` for constant, `Xing` for variable or
    /// average bit rate). A `Xing` or `VBRI` tag keeps the file on precise timing even when every frame has the same
    /// bit rate; an `Info` tag on a variable stream proves nothing (the frames decide).
    @Test func theTagIsAClaimAndTheFramesDecide() {
        let xing = scan(SyntheticMP3.stream(frames: 300, tag: .xing).data)
        #expect(!xing.isConstantBitRate && xing.tag == .xing && xing.bitRates.count == 1)
        #expect(xing.reason.contains("Xing tag"))
        let vbri = scan(SyntheticMP3.stream(frames: 300, tag: .vbri).data)
        #expect(!vbri.isConstantBitRate && vbri.tag == .vbri)
        let lyingInfo = scan(SyntheticMP3.stream(frames: 300, tag: .info, kbpsAt: [10: 128, 20: 32]).data)
        #expect(!lyingInfo.isConstantBitRate && lyingInfo.tag == .info)
        #expect(lyingInfo.reason.contains("3 bit rates"))
        let wrongCount = scan(SyntheticMP3.stream(frames: 300, tag: .info, tagFrameCount: 250).data)
        #expect(!wrongCount.isConstantBitRate)
        #expect(wrongCount.reason.contains("the Info tag counts 250 frames, the scan 299"), "\(wrongCount.reason)")
    }

    @Test func structuralProblemsAreNotProved() {
        let good = SyntheticMP3.stream(frames: 300, tag: .info)
        // Junk between two frames.
        var junk = good.data
        junk.insert(contentsOf: [0, 0, 0, 0, 0], at: good.offsets[150])
        #expect(scan(junk).reason.contains("no frame header at byte \(good.offsets[150])"))
        // An ID3 tag inside the audio (two files concatenated).
        var inner = good.data
        inner.insert(contentsOf: SyntheticMP3.id3v2(payload: 20), at: good.offsets[100])
        #expect(scan(inner).reason.contains("an ID3 tag inside the audio"))
        // A truncated last frame.
        #expect(scan(Array(good.data.dropLast(30))).reason.contains("the last frame is truncated"))
        // Unknown bytes after the audio.
        #expect(scan(good.data + [1, 2, 3]).reason.contains("3 bytes after the last frame"))
        // Unknown bytes before the audio.
        #expect(scan([0, 0] + good.data).reason.contains("no frame header where the audio starts"))
        // A free-format frame.
        var free = good.data
        free.replaceSubrange(good.offsets[20]..<good.offsets[20] + 4,
                             with: SyntheticMP3.bytes(SyntheticMP3.header(kbps: 64, sampleRate: 44_100, padding: false, freeFormat: true)))
        #expect(scan(free).reason.contains("free-format bit rate at frame 20"))
        // The sample rate or the channel count changes.
        #expect(scan(SyntheticMP3.stream(frames: 100, sampleRateAt: [60: 48_000]).data).reason.contains("the sample rate changes at frame 60"))
        #expect(scan(SyntheticMP3.stream(frames: 100, monoAt: [70: false]).data).reason.contains("the channel count changes at frame 70"))
        // Layer II.
        let layer2 = SyntheticMP3.bytes(SyntheticMP3.header(kbps: 64, sampleRate: 44_100, padding: false, layer: 2)) + [UInt8](repeating: 0, count: 400)
        #expect(scan(layer2).reason.contains("Layer 2, not Layer III"))
        // Nothing but a tag, and nothing at all.
        #expect(scan(SyntheticMP3.id3v2(payload: 50)).reason == "no MPEG audio frames")
        #expect(scan([]).reason == "no MPEG audio frames")
        // A malformed leading tag.
        #expect(scan(Array("ID3".utf8) + [4, 0, 0, 0xFF, 0, 0, 0] + good.data).reason.contains("malformed ID3v2 tag"))
    }

    /// Mutating any frame header's bit-rate or sample-rate field of a proved stream, or feeding random bytes, never
    /// yields a proof and never crashes the parser.
    @Test func mutationsAndRandomBytesAreNeverProved() {
        var rng = SeededRNG(seed: 2026)
        let good = SyntheticMP3.stream(frames: 120, tag: .info)
        #expect(scan(good.data).isConstantBitRate)
        for _ in 0..<300 {
            var bytes = good.data
            let frame = Int(rng.next() % UInt64(good.offsets.count))
            // Byte 2 of the header holds the bit-rate index (high nibble) and the sample-rate index (bits 3-2).
            let bit = [7, 6, 5, 4, 3, 2][Int(rng.next() % 6)]
            bytes[good.offsets[frame] + 2] ^= UInt8(1 << bit)
            #expect(!scan(bytes).isConstantBitRate, "frame \(frame) bit \(bit) flipped and still proved")
        }
        for _ in 0..<300 {
            let count = Int(rng.next() % 4_000)
            let random = (0..<count).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            #expect(!scan(random).isConstantBitRate)
            // A random truncation of the good stream cuts a frame, or, at a frame boundary, contradicts the Info tag's
            // frame count: never proved.
            let cut = Int(rng.next() % UInt64(good.data.count - 1))
            #expect(!scan(Array(good.data.prefix(cut))).isConstantBitRate)
        }
    }

    /// The import's decision: estimated timing only for a proved constant MP3 whose scanned duration agrees with
    /// AVFoundation's; precise for everything else.
    @Test func timingDecision() {
        let cbr = scan(SyntheticMP3.stream(frames: 500, tag: .info).data)
        let ms = cbr.audioDurationMs!
        #expect(TimingDecision.decide(codec: ".mp3", scan: cbr, preciseDurationMs: ms).timing == .estimatedCBR)
        #expect(TimingDecision.decide(codec: ".mp3", scan: cbr, preciseDurationMs: ms - 70).timing == .estimatedCBR)  // under 3 frames
        let off = TimingDecision.decide(codec: ".mp3", scan: cbr, preciseDurationMs: ms + 200)
        #expect(off.timing == .precise && off.reason.contains("differ by more than three frames"))
        #expect(TimingDecision.decide(codec: ".mp3", scan: cbr, preciseDurationMs: nil).timing == .precise)
        #expect(TimingDecision.decide(codec: "flac", scan: nil, preciseDurationMs: 1_000).reason == "not MP3")
        #expect(TimingDecision.decide(codec: ".mp3", scan: nil, preciseDurationMs: 1_000).timing == .precise)
        let vbr = scan(SyntheticMP3.stream(frames: 500, tag: .xing).data)
        let d = TimingDecision.decide(codec: ".mp3", scan: vbr, preciseDurationMs: vbr.audioDurationMs)
        #expect(d.timing == .precise && d.reason == vbr.reason)
    }

    /// An edition stored before the timing mode existed decodes with precise timing.
    @Test func membersWithoutATimingDecodeAsPrecise() throws {
        let json = #"{"assetID":"6A0F4D0B-3F43-4C39-9E0B-0D4A2B9C0411","fileName":"a.mp3","durationMs":1000}"#
        let m = try JSONDecoder().decode(EditionMember.self, from: Data(json.utf8))
        #expect(m.timing == .precise)
        let encoded = try JSONEncoder().encode(EditionMember(assetID: UUID(), fileName: "b.mp3", durationMs: 5, timing: .estimatedCBR))
        #expect(try JSONDecoder().decode(EditionMember.self, from: encoded).timing == .estimatedCBR)
    }
}
