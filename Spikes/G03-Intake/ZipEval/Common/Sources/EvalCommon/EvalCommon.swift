// Shared helpers for the G0.3 archive-library evaluation. Evidence code only.
import CryptoKit
import Darwin
import Foundation

/// Deterministic byte stream: the 8-byte word at index k is SplitMix64(seed + k), little endian.
/// Any range can be produced without generating the bytes before it.
public struct DeterministicBytes: Sendable {
    public let seed: UInt64
    public init(seed: UInt64) { self.seed = seed }

    @inline(__always) static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Fills `buffer` with the bytes at [offset, offset + buffer.count).
    public func fill(_ buffer: UnsafeMutableRawBufferPointer, offset: UInt64) {
        var i = 0
        let count = buffer.count
        while i < count {
            let absolute = offset + UInt64(i)
            let word = DeterministicBytes.mix(seed &+ (absolute >> 3))
            let byteIndex = Int(absolute & 7)
            buffer[i] = UInt8(truncatingIfNeeded: word >> (UInt64(byteIndex) * 8))
            i += 1
            // Fast path: whole aligned words.
            while i + 8 <= count, (offset + UInt64(i)) & 7 == 0 {
                let w = DeterministicBytes.mix(seed &+ ((offset + UInt64(i)) >> 3)).littleEndian
                buffer.storeBytes(of: w, toByteOffset: i, as: UInt64.self)
                i += 8
            }
        }
    }

    public func data(offset: UInt64, count: Int) -> Data {
        var d = Data(count: count)
        d.withUnsafeMutableBytes { fill($0, offset: offset) }
        return d
    }

    /// SHA-256 of the first `length` bytes, computed in 1 MiB chunks.
    public func sha256(length: UInt64) -> String {
        var hasher = SHA256()
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunk, alignment: 8)
        defer { buffer.deallocate() }
        var offset: UInt64 = 0
        while offset < length {
            let n = Int(min(UInt64(chunk), length - offset))
            let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[0..<n])
            fill(slice, offset: offset)
            hasher.update(bufferPointer: UnsafeRawBufferPointer(slice))
            offset += UInt64(n)
        }
        return hex(hasher.finalize())
    }
}

public func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
}

/// Process memory as the kernel accounts it. `physFootprint` is what jetsam limits on iOS;
/// `peakFootprint` is the lifetime peak of that ledger; `maxRSS` is getrusage's peak resident size.
public struct MemorySample: Sendable, CustomStringConvertible {
    public let physFootprint: UInt64
    public let peakFootprint: UInt64
    public let maxRSS: UInt64

    public static func now() -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let footprint = kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
        let peak = kr == KERN_SUCCESS ? UInt64(info.ledger_phys_footprint_peak) : 0
        return MemorySample(physFootprint: footprint, peakFootprint: peak, maxRSS: UInt64(usage.ru_maxrss))
    }

    public var description: String {
        "phys_footprint=\(mib(physFootprint)) peak_phys_footprint=\(mib(peakFootprint)) max_rss=\(mib(maxRSS))"
    }
}

public func mib(_ bytes: UInt64) -> String { String(format: "%.1fMiB", Double(bytes) / 1_048_576) }

public func elapsed(since start: ContinuousClock.Instant) -> String {
    let d = ContinuousClock.now - start
    let s = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    return String(format: "%.1fs", s)
}

public struct EvalFailure: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public let evalSeed: UInt64 = 0x5359_4C56_4941_0003  // "SYLVIA" + gate 3
public let smallText = Data(String(repeating: "Sylvia G0.3 deflated text entry.\n", count: 4096).utf8)
