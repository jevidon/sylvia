// G0.3 evaluation of upstream ZIPFoundation 0.9.20 on archives above 4 GiB.
//   zipeval-upstream write <archive> <big-bytes>   one stored deterministic entry + one deflated text entry
//   zipeval-upstream read <archive>                 list entries, stream each through SHA-256 (CRC32 checked)
//   zipeval-upstream open <archive>                 only open the archive (used for truncated copies)
import CryptoKit
import EvalCommon
import Foundation
import ZIPFoundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: zipeval-upstream write <archive> <big-bytes> | read <archive> | open <archive>")
    exit(2)
}
let url = URL(fileURLWithPath: args[2])
let start = ContinuousClock.now
let library = "upstream ZIPFoundation 0.9.20"

do {
    switch args[1] {
    case "write":
        guard args.count == 4, let bigBytes = UInt64(args[3]) else { throw EvalFailure("write needs <big-bytes>") }
        let archive = try Archive(url: url, accessMode: .create)
        let gen = DeterministicBytes(seed: evalSeed)
        try archive.addEntry(with: "audio/big.bin", type: .file, uncompressedSize: Int64(bigBytes),
                             compressionMethod: .none, bufferSize: 1 << 20) { position, size in
            gen.data(offset: UInt64(position), count: size)
        }
        try archive.addEntry(with: "text/small.txt", type: .file, uncompressedSize: Int64(smallText.count),
                             compressionMethod: .deflate, bufferSize: 1 << 16) { position, size in
            smallText.subdata(in: Int(position)..<Int(position) + size)
        }
        print("[\(library)] write ok archive=\(url.lastPathComponent) big=\(bigBytes) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
        print("[\(library)] expected big.bin sha256=\(gen.sha256(length: bigBytes))")
    case "read":
        let archive = try Archive(url: url, accessMode: .read)
        var count = 0
        for entry in archive {
            count += 1
            var hasher = SHA256()
            var bytes: UInt64 = 0
            let crc = try archive.extract(entry, bufferSize: 1 << 20, skipCRC32: false) { chunk in
                hasher.update(data: chunk)
                bytes += UInt64(chunk.count)
            }
            print("[\(library)] entry path=\(entry.path) type=\(entry.type) compressed=\(entry.isCompressed) uncompressedSize=\(entry.uncompressedSize) compressedSize=\(entry.compressedSize) streamed=\(bytes) crc32=\(String(crc, radix: 16)) sha256=\(hex(hasher.finalize()))")
        }
        print("[\(library)] read ok entries=\(count) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
    case "open":
        let archive = try Archive(url: url, accessMode: .read)
        let first = archive.makeIterator().next()
        print("[\(library)] open ACCEPTED (first entry: \(first?.path ?? "none")) elapsed=\(elapsed(since: start))")
    default:
        throw EvalFailure("unknown command \(args[1])")
    }
} catch {
    print("[\(library)] \(args[1]) FAILED: \(error) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
    exit(1)
}
