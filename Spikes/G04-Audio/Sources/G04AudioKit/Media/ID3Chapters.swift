import Foundation

/// A chapter of an audio asset in asset-local milliseconds.
public struct ChapterInfo: Codable, Hashable, Sendable {
    public var title: String
    public var startMs: Int64
    public var endMs: Int64
    public init(title: String, startMs: Int64, endMs: Int64) {
        self.title = title
        self.startMs = startMs
        self.endMs = endMs
    }
}

/// A bounds-checked reader for ID3v2.3/2.4 `CHAP` frames (the ID3 chapter addendum). On the iOS 26.5 simulator
/// AVFoundation reports these frames as chapter metadata groups (G0.4 codec matrix and MediaTests), so this parser
/// is the independent check of AVFoundation's result and the fallback when it reports none. The tag is untrusted
/// input: every length is checked and the tag size is capped.
public enum ID3Chapters {
    public static let maximumTagBytes = 16 * 1024 * 1024

    public enum ParseError: Error, Equatable, Sendable {
        case noTag
        case unsupportedVersion(UInt8)
        case tagTooLarge(Int)
        case truncated
    }

    public static func read(url: URL) throws -> [ChapterInfo] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 10), header.count == 10 else { throw ParseError.noTag }
        guard header.prefix(3) == Data("ID3".utf8) else { throw ParseError.noTag }
        let size = try syncsafe(header, at: 6)
        guard size <= maximumTagBytes else { throw ParseError.tagTooLarge(size) }
        guard let body = try handle.read(upToCount: size), body.count == size else { throw ParseError.truncated }
        return try parse(header: header, body: body)
    }

    /// Parses a complete tag: the 10-byte header and the body it announces.
    public static func parse(header: Data, body rawBody: Data) throws -> [ChapterInfo] {
        let h = [UInt8](header)
        let version = h[3]
        guard version == 3 || version == 4 else { throw ParseError.unsupportedVersion(version) }
        let flags = h[5]
        var body = [UInt8](rawBody)
        if flags & 0x80 != 0, version == 3 { body = removeUnsynchronisation(body) }
        var pos = 0
        if flags & 0x40 != 0 {  // extended header
            guard body.count >= 4 else { throw ParseError.truncated }
            let extSize = version == 4 ? try syncsafe(Data(body), at: 0) : Int(be32(body, 0))
            pos = version == 4 ? extSize : extSize + 4
            guard pos <= body.count else { throw ParseError.truncated }
        }
        var chapters: [ChapterInfo] = []
        for frame in try frames(body, from: pos, to: body.count, version: version) where frame.id == "CHAP" {
            if let c = try chapter(frame.payload, version: version) { chapters.append(c) }
        }
        return chapters.sorted { ($0.startMs, $0.endMs) < ($1.startMs, $1.endMs) }
    }

    struct Frame {
        var id: String
        var payload: [UInt8]
    }

    static func frames(_ bytes: [UInt8], from start: Int, to end: Int, version: UInt8) throws -> [Frame] {
        var result: [Frame] = []
        var pos = start
        while pos + 10 <= end {
            if bytes[pos] == 0 { break }  // padding
            guard let id = String(bytes: bytes[pos..<pos + 4], encoding: .ascii),
                  id.allSatisfy({ $0.isUppercase || $0.isNumber }) else { break }
            let size = version == 4 ? try syncsafe(Data(bytes[pos + 4..<pos + 8]), at: 0) : Int(be32(bytes, pos + 4))
            let payloadStart = pos + 10
            guard size >= 0, payloadStart + size <= end else { throw ParseError.truncated }
            result.append(Frame(id: id, payload: Array(bytes[payloadStart..<payloadStart + size])))
            pos = payloadStart + size
        }
        return result
    }

    static func chapter(_ p: [UInt8], version: UInt8) throws -> ChapterInfo? {
        guard let nul = p.firstIndex(of: 0) else { throw ParseError.truncated }
        let elementID = String(decoding: p[0..<nul], as: UTF8.self)
        let t = nul + 1
        guard t + 16 <= p.count else { throw ParseError.truncated }
        let startMs = Int64(be32(p, t)), endMs = Int64(be32(p, t + 4))
        var title = elementID
        for sub in try frames(p, from: t + 16, to: p.count, version: version) where sub.id == "TIT2" {
            if let s = text(sub.payload) { title = s }
        }
        guard endMs >= startMs else { return nil }
        return ChapterInfo(title: title, startMs: startMs, endMs: endMs)
    }

    static func text(_ p: [UInt8]) -> String? {
        guard let enc = p.first else { return nil }
        var body = Array(p.dropFirst())
        let s: String?
        switch enc {
        case 0:
            while body.last == 0 { body.removeLast() }
            s = String(bytes: body, encoding: .isoLatin1)
        case 1:
            while body.count >= 2, body[body.count - 1] == 0, body[body.count - 2] == 0 { body.removeLast(2) }
            s = String(bytes: body, encoding: .utf16)
        case 2:
            while body.count >= 2, body[body.count - 1] == 0, body[body.count - 2] == 0 { body.removeLast(2) }
            s = String(bytes: body, encoding: .utf16BigEndian)
        case 3:
            while body.last == 0 { body.removeLast() }
            s = String(bytes: body, encoding: .utf8)
        default:
            s = nil
        }
        return s
    }

    static func syncsafe(_ d: Data, at offset: Int) throws -> Int {
        let b = [UInt8](d)
        guard offset + 4 <= b.count else { throw ParseError.truncated }
        return (0..<4).reduce(0) { ($0 << 7) | Int(b[offset + $1] & 0x7f) }
    }

    static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
        (UInt32(b[o]) << 24) | (UInt32(b[o + 1]) << 16) | (UInt32(b[o + 2]) << 8) | UInt32(b[o + 3])
    }

    static func removeUnsynchronisation(_ b: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(b.count)
        var i = 0
        while i < b.count {
            out.append(b[i])
            if b[i] == 0xff, i + 1 < b.count, b[i + 1] == 0 { i += 2 } else { i += 1 }
        }
        return out
    }
}
