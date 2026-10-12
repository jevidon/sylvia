// G0.3 evaluation of Readium's ZIPFoundation fork 3.0.1 (module ReadiumZIPFoundation) on archives above 4 GiB.
//   zipeval-readium write <archive> <big-bytes>   one stored deterministic entry + one deflated text entry
//   zipeval-readium read <archive>                 list entries, stream each through SHA-256 (CRC32 checked)
//   zipeval-readium open <archive>                 only open the archive (used for truncated copies)
import CryptoKit
import EvalCommon
import Foundation
import ReadiumZIPFoundation

/// Mutable accumulator shared with the library's @Sendable consumer closure; the library calls it serially.
final class Accumulator: @unchecked Sendable {
    var hasher = SHA256()
    var bytes: UInt64 = 0
}

@main
struct ZipEvalReadium {
    static let library = "ReadiumZIPFoundation 3.0.1"

    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 3 else {
            print("usage: zipeval-readium write <archive> <big-bytes> | read <archive> | open <archive>")
            exit(2)
        }
        let url = URL(fileURLWithPath: args[2])
        let start = ContinuousClock.now
        do {
            switch args[1] {
            case "write":
                guard args.count == 4, let bigBytes = UInt64(args[3]) else { throw EvalFailure("write needs <big-bytes>") }
                let archive = try await Archive(url: url, accessMode: .create)
                let gen = DeterministicBytes(seed: evalSeed)
                try await archive.addEntry(with: "audio/big.bin", type: .file, uncompressedSize: Int64(bigBytes),
                                           compressionMethod: .none, bufferSize: 1 << 20) { position, size in
                    gen.data(offset: UInt64(position), count: size)
                }
                let text = smallText
                try await archive.addEntry(with: "text/small.txt", type: .file, uncompressedSize: Int64(text.count),
                                           compressionMethod: .deflate, bufferSize: 1 << 16) { position, size in
                    text.subdata(in: Int(position)..<Int(position) + size)
                }
                print("[\(library)] write ok archive=\(url.lastPathComponent) big=\(bigBytes) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
                print("[\(library)] expected big.bin sha256=\(gen.sha256(length: bigBytes))")
            case "read":
                let archive = try await Archive(url: url, accessMode: .read)
                let entries = try await archive.entries()
                for entry in entries {
                    let acc = Accumulator()
                    let crc = try await archive.extract(entry, bufferSize: 1 << 20, skipCRC32: false) { chunk in
                        acc.hasher.update(data: chunk)
                        acc.bytes += UInt64(chunk.count)
                    }
                    print("[\(library)] entry path=\(entry.path) type=\(entry.type) compressed=\(entry.isCompressed) uncompressedSize=\(entry.uncompressedSize) compressedSize=\(entry.compressedSize) streamed=\(acc.bytes) crc32=\(String(crc, radix: 16)) sha256=\(hex(acc.hasher.finalize()))")
                }
                print("[\(library)] read ok entries=\(entries.count) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
            case "open":
                let archive = try await Archive(url: url, accessMode: .read)
                let entries = try await archive.entries()
                print("[\(library)] open ACCEPTED (entries: \(entries.count)) elapsed=\(elapsed(since: start))")
            default:
                throw EvalFailure("unknown command \(args[1])")
            }
        } catch {
            print("[\(library)] \(args[1]) FAILED: \(error) elapsed=\(elapsed(since: start)) \(MemorySample.now())")
            exit(1)
        }
    }
}
