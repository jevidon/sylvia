import Foundation
import SylviaIntakeCore
import UniformTypeIdentifiers

/// Content the share extension accepts (plan 8.3): EPUB, PDF, plain text, Markdown and common audio.
public enum SupportedContent {
    public static let markdown = UTType("net.daringfireball.markdown") ?? UTType(importedAs: "net.daringfireball.markdown")

    /// Order matters: the first supported type a provider registers is the one loaded.
    public static let types: [UTType] = [.epub, .pdf, markdown, .plainText, .audio]

    /// Types that conform to plain text or audio but are not reading or listening material: source code and
    /// scripts (public.shell-script conforms to public.plain-text) and playlists.
    public static let excluded: [UTType] = [.sourceCode, .script, .executable, .playlist]

    public static func isSupported(_ type: UTType) -> Bool {
        !excluded.contains(where: { type.conforms(to: $0) }) && types.contains(where: { type.conforms(to: $0) })
    }

    public static func supportedType(conformingFrom identifiers: [String]) -> UTType? {
        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if isSupported(type) { return type }
        }
        return nil
    }

    /// Markdown file extensions mapped explicitly. On the iOS 26.5 simulator `UTType(filenameExtension: "markdown")`
    /// returns a dynamic type rather than net.daringfireball.markdown (only "md" is declared there), even inside an
    /// app that imports the type with more extensions (the system declaration wins); macOS maps both. Evidence:
    /// Docs/Stage0/G03-Intake.md, finding F3.
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    public static func supportedType(forFileExtension ext: String) -> UTType? {
        let lower = ext.lowercased()
        if markdownExtensions.contains(lower) { return markdown }
        guard !lower.isEmpty, let type = UTType(filenameExtension: lower) else { return nil }
        return isSupported(type) ? type : nil
    }
}

/// Bridges NSItemProvider to a HandoffSession. The provider's file is valid only inside its completion
/// handler, so the whole streaming copy happens there (Apple: "the file is deleted after the completion
/// handler returns"). Nothing is read into memory.
public struct ItemProviderIntake: Sendable {
    /// How long the provider may go without progress before the extension gives up (a stall, not a total
    /// time limit: an iCloud download that keeps moving is never cut off). Once copying has started there is no
    /// timeout; the copy is bounded by cancellation instead.
    public var providerStallTimeout: Duration
    /// The clock the stall timeout measures with: the continuous clock, except in the tests that measure stall
    /// behaviour, which advance a manual clock themselves.
    public var stallClock: StallClock

    public init(providerStallTimeout: Duration = .seconds(60), stallClock: StallClock = .continuous) {
        self.providerStallTimeout = providerStallTimeout
        self.stallClock = stallClock
    }

    /// Receives one shared item into the session. Throws `HandoffFailure` for anything that should produce the
    /// fallback screen. `openedInPlace` reports, for a file representation, whether the provider handed over its
    /// original file (true) or a temporary copy (false); evidence for the device checklist.
    ///
    /// `cancellation` acts in every phase: while the provider has not delivered its file yet (the loading Progress is
    /// cancelled and the call fails with `.cancelled` at once), while a coordinated read waits for another writer (the
    /// coordinator is cancelled), and during the copy (polled between chunks).
    public func receive(
        _ provider: NSItemProvider,
        into session: HandoffSession,
        cancellation: CancellationSignal = CancellationSignal(),
        progress: @escaping @Sendable (UInt64) -> Void = { _ in },
        openedInPlace: @escaping @Sendable (Bool) -> Void = { _ in }
    ) async throws -> HandoffManifest.Item {
        guard !cancellation.isCancelled else { throw HandoffFailure.cancelled }
        let registered = provider.registeredTypeIdentifiers
        if let type = SupportedContent.supportedType(conformingFrom: registered) {
            return try await receiveFileRepresentation(provider, type: type, session: session,
                                                       cancellation: cancellation, progress: progress, openedInPlace: openedInPlace)
        }
        if registered.contains(UTType.fileURL.identifier) {
            return try await receiveFileURL(provider, session: session, cancellation: cancellation, progress: progress)
        }
        if registered.contains(where: { UTType($0)?.conforms(to: .url) ?? false }) {
            // A web link, not a file: URL import belongs to the app (plan 8.1), not to the extension.
            throw HandoffFailure.notADurableFile
        }
        throw HandoffFailure.noSupportedItem
    }

    private func receiveFileRepresentation(
        _ provider: NSItemProvider, type: UTType, session: HandoffSession,
        cancellation: CancellationSignal, progress: @escaping @Sendable (UInt64) -> Void,
        openedInPlace: @escaping @Sendable (Bool) -> Void
    ) async throws -> HandoffManifest.Item {
        let gate = OnceGate<HandoffManifest.Item>()
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            // openInPlace: a provider that can (Files) hands over the original instead of first making a
            // temporary copy, which would double the space and time needed for a multi-GiB file.
            let loading = provider.loadFileRepresentation(for: type, openInPlace: true) { url, inPlace, error in
                guard gate.beginWork() else { return }  // timed out or cancelled already: do not copy
                if url != nil { openedInPlace(inPlace) }
                guard let url else {
                    gate.finish(.failure(error.map(Self.classify) ?? HandoffFailure.providerFailed))
                    return
                }
                let name = suggestedName.map { Self.appendExtension($0, of: url) } ?? url.lastPathComponent
                gate.finish(Result {
                    try Self.copyCoordinated(url, originalFilename: name, type: type, representation: .fileRepresentation,
                                             providerTypeIdentifier: type.identifier, session: session,
                                             cancellation: cancellation, progress: progress)
                })
            }
            gate.armStallTimeout(after: providerStallTimeout, progress: loading, clock: stallClock)
            gate.armCancellation(cancellation, progress: loading)
        }
    }

    private func receiveFileURL(
        _ provider: NSItemProvider, session: HandoffSession,
        cancellation: CancellationSignal, progress: @escaping @Sendable (UInt64) -> Void
    ) async throws -> HandoffManifest.Item {
        let gate = OnceGate<HandoffManifest.Item>()
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            let loading = provider.loadObject(ofClass: URL.self) { url, error in
                guard gate.beginWork() else { return }
                guard let url, url.isFileURL else {
                    gate.finish(.failure(url == nil ? (error.map(Self.classify) ?? HandoffFailure.providerFailed)
                                                    : HandoffFailure.notADurableFile))
                    return
                }
                guard let type = SupportedContent.supportedType(forFileExtension: url.pathExtension) else {
                    gate.finish(.failure(HandoffFailure.noSupportedItem))
                    return
                }
                gate.finish(Result {
                    try Self.copyCoordinated(url, originalFilename: url.lastPathComponent, type: type,
                                             representation: .fileURL, providerTypeIdentifier: UTType.fileURL.identifier,
                                             session: session, cancellation: cancellation, progress: progress)
                })
            }
            gate.armStallTimeout(after: providerStallTimeout, progress: loading, clock: stallClock)
            gate.armCancellation(cancellation, progress: loading)
        }
    }

    /// The URL may belong to a file provider (an in-place file or a direct file URL): take security-scoped
    /// access and coordinate the read while streaming the copy. A coordinated read can wait (for another process's
    /// coordinated write, or for a provider to make the file available); Cancel cancels that wait.
    static func copyCoordinated(
        _ url: URL, originalFilename: String, type: UTType, representation: HandoffManifest.Representation,
        providerTypeIdentifier: String, session: HandoffSession,
        cancellation: CancellationSignal, progress: (UInt64) -> Void
    ) throws -> HandoffManifest.Item {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let coordinator = CoordinatorBox(NSFileCoordinator(filePresenter: nil))
        let registration = cancellation.onCancel { coordinator.coordinator.cancel() }
        defer { cancellation.remove(registration) }
        // A cancel that lands between this check and the coordinated read calls cancel() before coordinate(...) has
        // started. That still ends the wait: a coordinator cancelled before its coordinate call returns at once with
        // NSUserCancelledError (pinned by the test "platform: a file coordinator cancelled before its coordinate
        // call ..." on host and simulator). The copier also checks the signal before its first read.
        guard !cancellation.isCancelled else { throw HandoffFailure.cancelled }
        var coordinationError: NSError?
        var result: Result<HandoffManifest.Item, any Error> = .failure(HandoffFailure.providerFailed)
        coordinator.coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = Result {
                try session.addItem(
                    copying: readURL, originalFilename: originalFilename, contentType: type.identifier,
                    preferredExtension: url.pathExtension.isEmpty ? type.preferredFilenameExtension : url.pathExtension,
                    representation: representation, providerTypeIdentifier: providerTypeIdentifier,
                    expectedLength: nil, isCancelled: { cancellation.isCancelled }, progress: progress
                )
            }
        }
        if let coordinationError {
            // NSFileCoordinator.cancel() makes a waiting coordinate call return NSUserCancelledError.
            if cancellation.isCancelled || (Self.classify(coordinationError) as? HandoffFailure) == .cancelled {
                throw HandoffFailure.cancelled
            }
            throw HandoffFailure.providerFailed
        }
        return try result.get()
    }

    static func classify(_ error: any Error) -> any Error {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError { return HandoffFailure.cancelled }
        return HandoffFailure.providerFailed
    }

    static func appendExtension(_ name: String, of url: URL) -> String {
        let ext = url.pathExtension
        guard !ext.isEmpty, (name as NSString).pathExtension.isEmpty else { return name }
        return name + "." + ext
    }
}

/// The time source of the provider stall timeout: the time elapsed since an origin, and a sleep. The share extension
/// uses `.continuous`. The stall tests inject a manual clock they advance in steps, so their outcome does not depend on
/// how the test process schedules its threads (M0 final review CC-02: with the continuous clock, a parallel test suite
/// delayed the simulated provider by more than the tests' 500 ms timeout between two 100 ms progress steps, and two of
/// thirteen full-suite runs failed). The product's 60 s timeout and the detector's logic are the same with either.
public struct StallClock: Sendable {
    public let now: @Sendable () -> Duration
    /// Returns after the duration, or earlier if the calling task is cancelled.
    public let sleep: @Sendable (Duration) async -> Void

    public init(now: @escaping @Sendable () -> Duration, sleep: @escaping @Sendable (Duration) async -> Void) {
        self.now = now
        self.sleep = sleep
    }

    /// `ContinuousClock`, which keeps counting while the device sleeps.
    public static var continuous: StallClock {
        let origin = ContinuousClock.now
        return StallClock(now: { ContinuousClock.now - origin }, sleep: { try? await Task.sleep(for: $0) })
    }
}

/// Progress is thread-safe but not marked Sendable.
///
/// What counts as movement: any change in the completed count, the total or the fraction completed. The Progress that
/// `loadFileRepresentation` returns wraps the provider's own Progress as a child: while the provider works, only
/// `fractionCompleted` moves and `completedUnitCount` stays 0 until the file is delivered (measured on macOS
/// Foundation; G0.3 report, finding F13). Watching the count alone cut off a provider that was still sending.
struct ProgressProbe: @unchecked Sendable {
    struct Snapshot: Equatable {
        let completed: Int64
        let total: Int64
        let fraction: Double
    }

    let progress: Progress
    init(_ progress: Progress) { self.progress = progress }
    var value: Snapshot {
        Snapshot(completed: progress.completedUnitCount, total: progress.totalUnitCount, fraction: progress.fractionCompleted)
    }
    func cancel() { progress.cancel() }
}

/// NSFileCoordinator is thread-safe (`cancel()` exists to be called from another thread) but not marked Sendable.
struct CoordinatorBox: @unchecked Sendable {
    let coordinator: NSFileCoordinator
    init(_ coordinator: NSFileCoordinator) { self.coordinator = coordinator }
}

/// Resumes a continuation exactly once, from the provider callback, the stall timeout or a cancel before delivery,
/// and stops the timeout and the early cancel from acting once copying has begun: both finish the gate only through
/// `finish(_:onlyBeforeWork: true)`, which checks under the same lock as `beginWork` (G0.3 review R4-04).
final class OnceGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var started = false
    private var done = false
    private var timeoutTask: Task<Void, Never>?
    /// Removes the cancel handler from the signal once the gate is finished.
    private var releaseCancellation: (@Sendable () -> Void)?
    /// Test seam: runs when the stall timeout has seen no progress for its whole duration, just before it tries to finish
    /// the gate, so a test can make the provider deliver in exactly that window.
    private let beforeStallTimeoutFires: @Sendable () -> Void

    init(beforeStallTimeoutFires: @escaping @Sendable () -> Void = {}) {
        self.beforeStallTimeoutFires = beforeStallTimeoutFires
    }

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        lock.withLock { self.continuation = continuation }
    }

    /// True if the caller may start work (the timeout has not fired).
    func beginWork() -> Bool {
        lock.withLock {
            guard !done else { return false }
            started = true
            timeoutTask?.cancel()
            return true
        }
    }

    func finish(_ result: Result<T, any Error>) {
        finish(result, onlyBeforeWork: false)
    }

    /// Cancel before the provider has delivered (G0.3 review R2-01): cancels the load's Progress, which asks the
    /// provider to stop, and fails at once with `.cancelled`. Once the completion handler has begun work, the copy path
    /// handles cancellation instead (the coordinated-read wait is cancelled, then the copier checks between chunks), so
    /// the caller is never resumed while the copy is still writing into its session.
    func armCancellation(_ cancellation: CancellationSignal, progress: Progress) {
        let probe = ProgressProbe(progress)
        let registration = cancellation.onCancel { [weak self] in
            guard let self else { return }
            if self.finish(.failure(HandoffFailure.cancelled), onlyBeforeWork: true) { probe.cancel() }
        }
        let release: @Sendable () -> Void = { cancellation.remove(registration) }
        let finishedAlready: Bool = lock.withLock {
            if done { return true }
            releaseCancellation = release
            return false
        }
        if finishedAlready { release() }
    }

    /// Resumes the continuation unless it already was; with `onlyBeforeWork`, also unless work has begun (checked under
    /// the same lock as `beginWork`). Returns whether this call finished the gate.
    @discardableResult
    private func finish(_ result: Result<T, any Error>, onlyBeforeWork: Bool) -> Bool {
        let (pending, release): (CheckedContinuation<T, any Error>?, (@Sendable () -> Void)?) = lock.withLock {
            guard !done, !(onlyBeforeWork && started) else { return (nil, nil) }
            done = true
            timeoutTask?.cancel()
            defer { continuation = nil; releaseCancellation = nil }
            return (continuation, releaseCancellation)
        }
        guard let pending else { return false }
        release?()
        pending.resume(with: result)
        return true
    }

    /// Fails with `providerTimedOut` (and cancels the load) if the provider's progress does not move for
    /// `duration` before work starts. A provider that delivers at the moment the timeout fires wins if its completion
    /// handler reaches `beginWork` first: the timeout then neither resumes the caller nor cancels the load. (The first
    /// version checked `started` and later finished the gate unconditionally, so a delivery between the two started the
    /// copy and the share still ended as timed out while the copy wrote into a session the caller then discarded.)
    func armStallTimeout(after duration: Duration, progress: Progress, clock: StallClock = .continuous) {
        let probe = ProgressProbe(progress)
        let task = Task { [weak self] in
            var lastValue = probe.value
            var lastChange = clock.now()
            let tick = min(duration, .milliseconds(250))
            while !Task.isCancelled {
                await clock.sleep(tick)
                guard let self, !Task.isCancelled else { return }
                if self.lock.withLock({ self.started || self.done }) { return }
                let value = probe.value
                if value != lastValue {
                    lastValue = value
                    lastChange = clock.now()
                } else if clock.now() - lastChange >= duration {
                    self.beforeStallTimeoutFires()
                    if self.finish(.failure(HandoffFailure.providerTimedOut), onlyBeforeWork: true) { probe.cancel() }
                    return
                }
            }
        }
        lock.withLock {
            if done || started { task.cancel() } else { timeoutTask = task }
        }
    }
}
