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

    public init(providerStallTimeout: Duration = .seconds(60)) {
        self.providerStallTimeout = providerStallTimeout
    }

    /// Receives one shared item into the session. Throws `HandoffFailure` for anything that should produce the
    /// fallback screen. `openedInPlace` reports, for a file representation, whether the provider handed over its
    /// original file (true) or a temporary copy (false); evidence for the device checklist.
    public func receive(
        _ provider: NSItemProvider,
        into session: HandoffSession,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (UInt64) -> Void = { _ in },
        openedInPlace: @escaping @Sendable (Bool) -> Void = { _ in }
    ) async throws -> HandoffManifest.Item {
        let registered = provider.registeredTypeIdentifiers
        if let type = SupportedContent.supportedType(conformingFrom: registered) {
            return try await receiveFileRepresentation(provider, type: type, session: session,
                                                       isCancelled: isCancelled, progress: progress, openedInPlace: openedInPlace)
        }
        if registered.contains(UTType.fileURL.identifier) {
            return try await receiveFileURL(provider, session: session, isCancelled: isCancelled, progress: progress)
        }
        if registered.contains(where: { UTType($0)?.conforms(to: .url) ?? false }) {
            // A web link, not a file: URL import belongs to the app (plan 8.1), not to the extension.
            throw HandoffFailure.notADurableFile
        }
        throw HandoffFailure.noSupportedItem
    }

    private func receiveFileRepresentation(
        _ provider: NSItemProvider, type: UTType, session: HandoffSession,
        isCancelled: @escaping @Sendable () -> Bool, progress: @escaping @Sendable (UInt64) -> Void,
        openedInPlace: @escaping @Sendable (Bool) -> Void
    ) async throws -> HandoffManifest.Item {
        let gate = OnceGate<HandoffManifest.Item>()
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            // openInPlace: a provider that can (Files) hands over the original instead of first making a
            // temporary copy, which would double the space and time needed for a multi-GiB file.
            let loading = provider.loadFileRepresentation(for: type, openInPlace: true) { url, inPlace, error in
                guard gate.beginWork() else { return }  // timed out already: do not copy
                if url != nil { openedInPlace(inPlace) }
                guard let url else {
                    gate.finish(.failure(error.map(Self.classify) ?? HandoffFailure.providerFailed))
                    return
                }
                let name = suggestedName.map { Self.appendExtension($0, of: url) } ?? url.lastPathComponent
                gate.finish(Result {
                    try Self.copyCoordinated(url, originalFilename: name, type: type, representation: .fileRepresentation,
                                             providerTypeIdentifier: type.identifier, session: session,
                                             isCancelled: isCancelled, progress: progress)
                })
            }
            gate.armStallTimeout(after: providerStallTimeout, progress: loading)
        }
    }

    private func receiveFileURL(
        _ provider: NSItemProvider, session: HandoffSession,
        isCancelled: @escaping @Sendable () -> Bool, progress: @escaping @Sendable (UInt64) -> Void
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
                                             session: session, isCancelled: isCancelled, progress: progress)
                })
            }
            gate.armStallTimeout(after: providerStallTimeout, progress: loading)
        }
    }

    /// The URL may belong to a file provider (an in-place file or a direct file URL): take security-scoped
    /// access and coordinate the read while streaming the copy.
    static func copyCoordinated(
        _ url: URL, originalFilename: String, type: UTType, representation: HandoffManifest.Representation,
        providerTypeIdentifier: String, session: HandoffSession,
        isCancelled: () -> Bool, progress: (UInt64) -> Void
    ) throws -> HandoffManifest.Item {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<HandoffManifest.Item, any Error> = .failure(HandoffFailure.providerFailed)
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = Result {
                try session.addItem(
                    copying: readURL, originalFilename: originalFilename, contentType: type.identifier,
                    preferredExtension: url.pathExtension.isEmpty ? type.preferredFilenameExtension : url.pathExtension,
                    representation: representation, providerTypeIdentifier: providerTypeIdentifier,
                    expectedLength: nil, isCancelled: isCancelled, progress: progress
                )
            }
        }
        if coordinationError != nil { throw HandoffFailure.providerFailed }
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

/// Resumes a continuation exactly once, from either the provider callback or the timeout, and stops the
/// timeout from firing once copying has begun.
final class OnceGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var started = false
    private var done = false
    private var timeoutTask: Task<Void, Never>?

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
        let pending: CheckedContinuation<T, any Error>? = lock.withLock {
            guard !done else { return nil }
            done = true
            timeoutTask?.cancel()
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }

    /// Fails with `providerTimedOut` (and cancels the load) if the provider's progress does not move for
    /// `duration` before work starts.
    func armStallTimeout(after duration: Duration, progress: Progress) {
        let probe = ProgressProbe(progress)
        let task = Task { [weak self] in
            var lastValue = probe.value
            var lastChange = ContinuousClock.now
            let tick = min(duration, .milliseconds(250))
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard let self, !Task.isCancelled else { return }
                if self.lock.withLock({ self.started || self.done }) { return }
                let value = probe.value
                if value != lastValue {
                    lastValue = value
                    lastChange = .now
                } else if ContinuousClock.now - lastChange >= duration {
                    probe.cancel()
                    self.finish(.failure(HandoffFailure.providerTimedOut))
                    return
                }
            }
        }
        lock.withLock {
            if done || started { task.cancel() } else { timeoutTask = task }
        }
    }
}
