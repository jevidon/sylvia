import Darwin
import Foundation

/// Process memory as the kernel accounts it.
/// - `physFootprint`: the ledger iOS jetsam enforces (what an extension's memory limit is measured against).
/// - `peakPhysFootprint`: lifetime peak of that ledger for this process.
/// - `maxRSS`: getrusage peak resident set size (bytes on Darwin).
public struct MemorySample: Sendable, Codable, Equatable, CustomStringConvertible {
    public let physFootprint: UInt64
    public let peakPhysFootprint: UInt64
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
        return MemorySample(
            physFootprint: kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0,
            peakPhysFootprint: kr == KERN_SUCCESS ? UInt64(info.ledger_phys_footprint_peak) : 0,
            maxRSS: UInt64(usage.ru_maxrss)
        )
    }

    public var description: String {
        "phys_footprint=\(mib(physFootprint)) peak_phys_footprint=\(mib(peakPhysFootprint)) max_rss=\(mib(maxRSS))"
    }

    /// `task_vm_info.limit_bytes_remaining`: bytes left before this process's memory limit, as the kernel reports it.
    /// os/proc.h documents `os_proc_available_memory()` as equivalent but returning 0 for a process that "is not an
    /// app", which may include extensions; this reads the field directly. nil when the kernel did not fill the field.
    public static func limitBytesRemaining() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS, let offset = MemoryLayout<task_vm_info_data_t>.offset(of: \.limit_bytes_remaining) else {
            return nil
        }
        let filled = Int(count) * MemoryLayout<natural_t>.size
        guard filled >= offset + MemoryLayout<UInt64>.size else { return nil }
        return info.limit_bytes_remaining
    }
}

/// Samples phys_footprint on a background thread so a peak inside one operation can be reported even when the
/// process's lifetime peak was set earlier (for example by test-runner start-up).
public final class FootprintSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var running = true
    private let interval: TimeInterval
    private var thread: Thread?

    public init(interval: TimeInterval = 0.01) { self.interval = interval }

    public func start() {
        lock.withLock { peak = MemorySample.now().physFootprint }
        let thread = Thread { [self] in
            while lock.withLock({ running }) {
                let current = MemorySample.now().physFootprint
                lock.withLock { peak = max(peak, current) }
                Thread.sleep(forTimeInterval: interval)
            }
        }
        self.thread = thread
        thread.start()
    }

    /// Stops sampling and returns the highest phys_footprint seen while running.
    public func stop() -> UInt64 {
        let current = MemorySample.now().physFootprint
        return lock.withLock {
            running = false
            peak = max(peak, current)
            return peak
        }
    }
}

public func mib(_ bytes: UInt64) -> String { String(format: "%.1f MiB", Double(bytes) / 1_048_576) }

/// Deterministic byte stream for generated fixtures: the 8-byte little-endian word at index k is
/// SplitMix64(seed + k). Any range can be produced without generating the bytes before it, so a reader can
/// verify a multi-GiB file without a stored copy.
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
        let count = buffer.count
        var i = 0
        // Unaligned head, byte by byte.
        while i < count, (offset + UInt64(i)) & 7 != 0 {
            buffer[i] = byte(at: offset + UInt64(i))
            i += 1
        }
        // Aligned words.
        while i + 8 <= count {
            let word = DeterministicBytes.mix(seed &+ ((offset + UInt64(i)) >> 3)).littleEndian
            buffer.storeBytes(of: word, toByteOffset: i, as: UInt64.self)
            i += 8
        }
        // Tail.
        while i < count {
            buffer[i] = byte(at: offset + UInt64(i))
            i += 1
        }
    }

    @inline(__always) func byte(at absolute: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: DeterministicBytes.mix(seed &+ (absolute >> 3)) >> ((absolute & 7) * 8))
    }

    public func data(offset: UInt64, count: Int) -> Data {
        var d = Data(count: count)
        d.withUnsafeMutableBytes { fill($0, offset: offset) }
        return d
    }

    /// Writes `length` bytes to a new file with a fixed 1 MiB buffer.
    public func writeFile(_ url: URL, length: UInt64) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw IntakeIOError("create") }
        defer { close(fd) }
        let chunk = 1 << 20
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunk, alignment: 16)
        defer { buffer.deallocate() }
        var offset: UInt64 = 0
        while offset < length {
            let n = Int(min(UInt64(chunk), length - offset))
            let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[0..<n])
            fill(slice, offset: offset)
            try Durability.writeAll(fd: fd, UnsafeRawBufferPointer(slice))
            offset += UInt64(n)
        }
        try Durability.fullSync(fd: fd)
    }
}
