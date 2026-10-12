import Foundation

public enum CRC32 {
    private static let table: [UInt32] = (0 ..< 256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0 ..< 8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum<D: DataProtocol>(_ data: D) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

/// Test support: replaces an ASCII placeholder with a same-length string inside STORED entries of a ZIP and
/// rewrites their CRC-32 in both headers. Used to point the hostile fixture at a loopback port chosen at runtime.
public enum StoredEntryPatcher {
    public enum PatchError: Error, Equatable { case lengthMismatch, notStored(String), unreadable }

    public static func replace(_ placeholder: String, with replacement: String, in archive: Data) throws -> (Data, patchedEntries: [String]) {
        guard placeholder.utf8.count == replacement.utf8.count else { throw PatchError.lengthMismatch }
        let report = ZIPPreflight.inspect(data: archive)
        guard !report.entries.isEmpty else { throw PatchError.unreadable }
        var out = archive
        let needle = Data(placeholder.utf8)
        let swap = Data(replacement.utf8)
        var patched: [String] = []
        let reader = ByteReader(archive)

        // Locate central directory records to rewrite their CRC.
        var centralOffsets: [String: Int] = [:]
        if let eocd = (0 ... archive.count - 22).reversed().first(where: { reader.u32($0) == 0x0605_4B50 }) {
            var p = Int(reader.u32(eocd + 16))
            for _ in 0 ..< Int(reader.u16(eocd + 10)) {
                let n = Int(reader.u16(p + 28)), x = Int(reader.u16(p + 30)), c = Int(reader.u16(p + 32))
                let name = String(decoding: archive.subdata(in: p + 46 ..< p + 46 + n), as: UTF8.self)
                centralOffsets[name] = p
                p += 46 + n + x + c
            }
        }

        for entry in report.entries {
            let o = Int(entry.localHeaderOffset)
            let start = o + 30 + Int(reader.u16(o + 26)) + Int(reader.u16(o + 28))
            let end = start + Int(entry.compressedSize)
            let body = archive.subdata(in: start ..< end)
            guard body.range(of: needle) != nil else { continue }
            guard entry.method == 0 else { throw PatchError.notStored(entry.name) }
            var newBody = body
            while let r = newBody.range(of: needle) { newBody.replaceSubrange(r, with: swap) }
            out.replaceSubrange(start ..< end, with: newBody)
            let crc = CRC32.checksum(newBody)
            withUnsafeBytes(of: crc.littleEndian) { bytes in
                out.replaceSubrange(o + 14 ..< o + 18, with: bytes)
                if let c = centralOffsets[entry.name] { out.replaceSubrange(c + 16 ..< c + 20, with: bytes) }
            }
            patched.append(entry.name)
        }
        return (out, patched)
    }
}
