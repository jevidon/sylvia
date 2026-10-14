import Foundation
@testable import SylviaImportHandoff
import SylviaIntakeCore

/// A throwaway App Group + app container pair for one test.
struct Sandbox {
    let root: URL
    var inbox: URL { root.appendingPathComponent("group/Intake/Handoffs", isDirectory: true) }
    var staging: URL { root.appendingPathComponent("app/Staging", isDirectory: true) }
    var journalURL: URL { staging.appendingPathComponent("journal.json") }
    var sources: URL { root.appendingPathComponent("sources", isDirectory: true) }

    init() throws {
        root = try TestDirectory.make()   // removed when the test ends (TemporaryFiles.swift)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    func environment(faults: any FaultInjecting = NoFaults(), buffer: Int = 64 << 10,
                     capacity: UInt64? = nil, itemLimit: UInt64 = 20 << 30) -> HandoffEnvironment {
        HandoffEnvironment(
            inbox: inbox, producerBundleIdentifier: "com.jevidon.sylvia.spike.intake.share", producerBuildVersion: "1",
            faults: faults,
            availableCapacity: { _ in capacity },
            itemLimit: itemLimit, bufferSize: buffer
        )
    }

    /// Deterministic source file of `length` bytes.
    func source(_ name: String, length: UInt64, seed: UInt64 = 1) throws -> URL {
        let url = sources.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try DeterministicBytes(seed: seed).writeFile(url, length: length)
        return url
    }

    func journal() throws -> IntakeJournal { try IntakeJournal(url: journalURL) }

    func scanner(now: @escaping @Sendable () -> Date = { Date() }, hook: @escaping @Sendable (AcceptStep) throws -> Void = { _ in }) throws -> InboxScanner {
        InboxScanner(inbox: inbox, stagingRoot: staging, journal: try journal(), now: now, hook: hook)
    }

    /// Every handoff.json under the inbox (there must never be one for incomplete bytes).
    func manifests() -> [URL] {
        let enumerator = FileManager.default.enumerator(atPath: inbox.path)
        var found: [URL] = []
        while let relative = enumerator?.nextObject() as? String {
            if (relative as NSString).lastPathComponent == HandoffManifest.fileName {
                found.append(inbox.appendingPathComponent(relative))
            }
        }
        return found
    }

    func inboxEntries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []).sorted()
    }
}

/// Progress and the provider completion are thread-safe but not marked Sendable; tests hand them to a queue.
struct SendableProgress: @unchecked Sendable {
    let progress: Progress
    init(_ progress: Progress) { self.progress = progress }
}

struct SendableCompletion: @unchecked Sendable {
    let completion: (URL?, Bool, (any Error)?) -> Void
    init(_ completion: @escaping (URL?, Bool, (any Error)?) -> Void) { self.completion = completion }
}

/// A user's Cancel landing at one step of the write sequence: cancels the signal when the step is reached, and lets
/// the step itself succeed.
final class CancelAtStep: FaultInjecting, @unchecked Sendable {
    let step: HandoffWriteStep
    let signal: CancellationSignal
    private let hit = Flag()
    init(step: HandoffWriteStep, signal: CancellationSignal) {
        self.step = step
        self.signal = signal
    }
    func reach(_ reached: HandoffWriteStep) throws {
        guard reached == step else { return }
        hit.set()
        signal.cancel()
    }
    var reached: Bool { hit.isSet }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
