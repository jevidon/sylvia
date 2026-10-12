import Foundation
import GRDB

/// Acknowledged-capture save latency (plan 19.2: p95 <= 200 ms). Measures `saveCapture` from call to
/// return, which includes the commit and its WAL sync under the given durability policy. Results are
/// indicative for the environment they ran in; device numbers are a device-checklist item.
public enum LatencyBench {
    public struct Result: Sendable, CustomStringConvertible {
        public let durability: String
        public let samples: Int
        public let p50Ms: Double
        public let p95Ms: Double
        public let p99Ms: Double
        public let maxMs: Double

        public var description: String {
            String(format: "%@: n=%d p50=%.3f ms p95=%.3f ms p99=%.3f ms max=%.3f ms", durability, samples, p50Ms, p95Ms, p99Ms, maxMs)
        }
    }

    /// Saves `iterations` captures (two anchors and a comment each, like the crash drill) into a
    /// library at `root` that already holds `preload` captures.
    public static func run(root: URL, durability: DurabilityPolicy, iterations: Int, preload: Int = 500) throws -> Result {
        var options = StoreOptions()
        options.durability = durability
        let layout = LibraryLayout(root: root)
        try CrashDrill.seed(layout, durability: durability)
        let store = try LibraryStore.open(layout, options: options)
        defer { try? store.close() }
        for n in 0..<preload { try store.saveCapture(CrashDrill.command(1_000_000 + n)) }
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        let clock = ContinuousClock()
        for n in 0..<iterations {
            let command = CrashDrill.command(n)
            let elapsed = try clock.measure { try store.saveCapture(command) }
            samples.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        samples.sort()
        func percentile(_ p: Double) -> Double {
            samples[min(samples.count - 1, Int((p * Double(samples.count)).rounded(.up)) - 1)]
        }
        return Result(durability: durability.description, samples: samples.count, p50Ms: percentile(0.50),
                      p95Ms: percentile(0.95), p99Ms: percentile(0.99), maxMs: samples.last ?? 0)
    }
}
