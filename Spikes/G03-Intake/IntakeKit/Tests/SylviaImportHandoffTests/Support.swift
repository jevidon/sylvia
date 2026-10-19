import Foundation
@testable import SylviaImportHandoff
import SylviaIntakeCore
import Testing

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

/// The stall timeout's clock for the stall tests (`StallClock`; M0 final review CC-02): its time moves only when the
/// test calls `advance(by:)`, which wakes every sleeper whose deadline has come. A test moves the provider's progress
/// and this clock step by step and waits, between steps, until the stall timeout's task is asleep again, so the timeout
/// sees exactly the steps the test made, however the test threads are scheduled.
final class ManualStallClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    private var nextID = 0
    private var sleepers: [Int: (deadline: Duration, continuation: CheckedContinuation<Void, Never>)] = [:]

    var clock: StallClock {
        StallClock(now: { [self] in now }, sleep: { [self] duration in await sleep(for: duration) })
    }

    var now: Duration { lock.withLock { current } }
    /// Tasks waiting in `sleep(for:)`.
    var sleeping: Int { lock.withLock { sleepers.count } }

    func sleep(for duration: Duration) async {
        let id: Int = lock.withLock {
            nextID += 1
            return nextID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Under the lock, so a cancellation either finds this sleeper or is seen here (the task's flag is set
                // before its cancellation handler runs).
                let resumeNow: Bool = lock.withLock {
                    if Task.isCancelled || duration <= .zero { return true }
                    sleepers[id] = (current + duration, continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            let continuation = lock.withLock { sleepers.removeValue(forKey: id)?.continuation }
            continuation?.resume()
        }
    }

    func advance(by duration: Duration) {
        let due: [CheckedContinuation<Void, Never>] = lock.withLock {
            current += duration
            let ready = sleepers.filter { $0.value.deadline <= current }
            for key in ready.keys { sleepers[key] = nil }
            return ready.map(\.value.continuation)
        }
        for continuation in due { continuation.resume() }
    }
}

/// Waits until `condition` holds, polling every millisecond. Real time is used here only to wait for the other task
/// to catch up, never as a measurement; after 30 s the wait records an issue and throws instead of hanging the suite.
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    let started = ContinuousClock.now
    while !condition() {
        if ContinuousClock.now - started > .seconds(30) {
            Issue.record("waited 30 s, and still not: \(what)")
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// The provider's completion handler, kept by its load handler until the test delivers the file.
final class CompletionHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var held: SendableCompletion?
    func keep(_ completion: @escaping (URL?, Bool, (any Error)?) -> Void) { lock.withLock { held = SendableCompletion(completion) } }
    var completion: SendableCompletion? { lock.withLock { held } }
}
