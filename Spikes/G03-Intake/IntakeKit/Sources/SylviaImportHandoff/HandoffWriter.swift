import Darwin
import Foundation
import SylviaIntakeCore

/// Everything the extension-side writer needs, injectable for tests.
public struct HandoffEnvironment: Sendable {
    /// `<App Group>/Intake/Handoffs`.
    public var inbox: URL
    public var producerBundleIdentifier: String
    public var producerBuildVersion: String
    public var faults: any FaultInjecting
    /// Available bytes on the inbox volume, or nil when unknown.
    public var availableCapacity: @Sendable (URL) -> UInt64?
    /// Space kept free beyond the item itself.
    public var spaceMargin: UInt64
    /// Per-item byte limit (plan 8.3 proposes 20 GiB for audio, the largest class).
    public var itemLimit: UInt64
    public var bufferSize: Int
    public var now: @Sendable () -> Date

    public init(
        inbox: URL,
        producerBundleIdentifier: String,
        producerBuildVersion: String,
        faults: any FaultInjecting = NoFaults(),
        availableCapacity: @escaping @Sendable (URL) -> UInt64? = HandoffEnvironment.volumeAvailableCapacity,
        spaceMargin: UInt64 = 64 << 20,
        itemLimit: UInt64 = 20 << 30,
        bufferSize: Int = StreamingCopier.defaultBufferSize,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.inbox = inbox
        self.producerBundleIdentifier = producerBundleIdentifier
        self.producerBuildVersion = producerBuildVersion
        self.faults = faults
        self.availableCapacity = availableCapacity
        self.spaceMargin = spaceMargin
        self.itemLimit = itemLimit
        self.bufferSize = bufferSize
        self.now = now
    }

    public static let volumeAvailableCapacity: @Sendable (URL) -> UInt64? = VolumeSpace.availableCapacity
}

/// Why a handoff did not complete. Each case maps to an actionable fallback (FallbackRoute).
public enum HandoffFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case noSupportedItem
    case notADurableFile
    /// The provider handed over a folder: an EPUB stored unpacked as a package directory (as iCloud Drive or a Mac's
    /// Books library can keep one). A share can take single files only.
    case folderNotFile
    case providerFailed
    case providerTimedOut
    case insufficientSpace(additionalBytesNeeded: UInt64?)
    case itemTooLarge(limit: UInt64)
    case sourceChanged
    case cancelled
    case writeFailed(String)
    case tooManyItems
    /// The handoff's manifest would exceed the size the app's scan reads (`HandoffManifest.maxBytes`): only file names
    /// and type identifiers near their limits, full of characters JSON escapes, come near it (G0.3 review R4-02).
    case manifestTooLarge

    public var description: String {
        switch self {
        case .noSupportedItem: "no supported file in the shared items"
        case .notADurableFile: "the sharing app did not provide a file Sylvia can keep"
        case .folderNotFile: "the sharing app offered a folder, not a single file"
        case .providerFailed: "the sharing app could not provide the file"
        case .providerTimedOut: "the sharing app did not provide the file in time"
        case let .insufficientSpace(n): "not enough space" + (n.map { " (\($0) more bytes needed)" } ?? "")
        case let .itemTooLarge(limit): "file is larger than the \(limit)-byte limit"
        case .sourceChanged: "the file changed while it was being copied"
        case .cancelled: "cancelled"
        case let .writeFailed(reason): "could not write the copy: \(reason)"
        case .tooManyItems: "too many items in one share"
        case .manifestTooLarge: "the shared files' names are too long to record in one share"
        }
    }

    public static func from(_ error: any Error) -> HandoffFailure {
        switch error {
        case let failure as HandoffFailure: return failure
        case let copy as CopyFailure:
            switch copy {
            case .cancelled: return .cancelled
            case .sourceChangedDuringCopy, .lengthMismatch: return .sourceChanged
            case let .exceedsLimit(limit): return .itemTooLarge(limit: limit)
            case .sourceNotRegularFile: return .notADurableFile
            case .sourceIsFolder: return .folderNotFile
            }
        case let io as IntakeIOError:
            return io.isOutOfSpace ? .insufficientSpace(additionalBytesNeeded: nil) : .writeFailed(io.description)
        default:
            return .writeFailed(String(describing: type(of: error)))
        }
    }
}

/// Proof that a handoff is durable. Only `HandoffSession.commit()` creates one, so the extension can only
/// report receipt with a receipt in hand.
public struct HandoffReceipt: Sendable, Equatable {
    public let handoffID: UUID
    public let itemCount: Int
    public let totalBytes: UInt64
    fileprivate init(handoffID: UUID, itemCount: Int, totalBytes: UInt64) {
        self.handoffID = handoffID
        self.itemCount = itemCount
        self.totalBytes = totalBytes
    }
}

/// One share request's write sequence:
///   check space -> create Handoffs/<id>/items -> stream each item (fsync each) -> sync items/ ->
///   write handoff.json.tmp-* -> fsync -> rename to handoff.json (no replace) -> sync Handoffs/<id> -> receipt.
/// On any failure the directory is removed and no receipt exists. If the process dies instead, the directory
/// has no handoff.json and the app's scanner treats it as incomplete (InboxScanner).
///
/// Calls are serialized by the caller (one item at a time); the lock only guards state transitions.
public final class HandoffSession: @unchecked Sendable {
    public let handoffID: UUID
    public let directory: URL
    private let environment: HandoffEnvironment
    private let lock = NSLock()
    private var items: [HandoffManifest.Item] = []
    private var directoryCreated = false
    private var finished = false

    public init(environment: HandoffEnvironment, handoffID: UUID = UUID()) {
        self.environment = environment
        self.handoffID = handoffID
        self.directory = environment.inbox.appendingPathComponent(handoffID.uuidString, isDirectory: true)
    }

    public var itemCount: Int { lock.withLock { items.count } }

    /// Streams one file into the handoff. The source URL only needs to be readable for the duration of the call.
    @discardableResult
    public func addItem(
        copying source: URL,
        originalFilename: String,
        contentType: String,
        preferredExtension: String?,
        representation: HandoffManifest.Representation,
        providerTypeIdentifier: String,
        expectedLength: UInt64?,
        isCancelled: () -> Bool = { false },
        progress: (UInt64) -> Void = { _ in }
    ) throws -> HandoffManifest.Item {
        let ordinal: Int = try lock.withLock {
            guard !finished else { throw HandoffFailure.writeFailed("session already finished") }
            guard items.count < HandoffManifest.maxItems else { throw HandoffFailure.tooManyItems }
            return items.count
        }
        let faults = environment.faults

        // Size known in advance: refuse before copying anything.
        var knownLength = expectedLength
        if knownLength == nil, let info = try? Durability.lstatInfo(source), info.isRegularFile {
            knownLength = UInt64(info.st_size)
        }
        try faults.reach(.checkSpace)
        if let knownLength {
            if knownLength > environment.itemLimit { throw HandoffFailure.itemTooLarge(limit: environment.itemLimit) }
            if let available = environment.availableCapacity(environment.inbox) {
                let needed = knownLength + environment.spaceMargin
                if needed > available {
                    throw HandoffFailure.insufficientSpace(additionalBytesNeeded: needed - available)
                }
            }
        }

        if !lock.withLock({ directoryCreated }) {
            try faults.reach(.createStagingDirectory)
            try FileManager.default.createDirectory(at: environment.inbox, withIntermediateDirectories: true)
            // Staging class (plan 17.1): keep handoffs out of device backup. The extension can run before the app has
            // ever launched, so it marks the inbox itself; the app's bootstrap marks it again. Best effort: a handoff
            // that is backed up is not a safety problem, so a failure here does not stop the copy.
            if !VolumeSpace.isExcludedFromBackup(environment.inbox) { try? VolumeSpace.excludeFromBackup(environment.inbox) }
            try Durability.createFreshDirectory(directory)
            try Durability.createFreshDirectory(directory.appendingPathComponent("items", isDirectory: true))
            lock.withLock { directoryCreated = true }
        }

        let storedPath = HandoffManifest.storedPath(ordinal: ordinal, preferredExtension: preferredExtension)
        let destination = directory.appendingPathComponent(storedPath)
        let copier = StreamingCopier(bufferSize: environment.bufferSize, faults: faults)
        let result = try copier.copy(
            from: source, toNewFile: destination, expectedLength: expectedLength,
            limit: environment.itemLimit, isCancelled: isCancelled, progress: progress
        )
        let item = HandoffManifest.Item(
            itemID: UUID(), storedPath: storedPath,
            originalFilename: HandoffSession.cleanFilename(originalFilename, fallback: "item-\(ordinal)"),
            contentType: contentType, byteCount: result.byteCount, sha256: result.sha256,
            representation: representation, providerTypeIdentifier: providerTypeIdentifier
        )
        lock.withLock { items.append(item) }
        return item
    }

    /// Writes handoff.json atomically and last. Returns the receipt only after the rename is durable.
    ///
    /// `isCancelled` is checked once more before the commit starts: the copier polls it only before each read, so a
    /// Cancel tapped after the last byte was read (while the item is synced and verified) would otherwise still end in
    /// "Received" (G0.3 review R2-01). Once the commit has started it runs to the end (milliseconds), and its receipt
    /// stands.
    public func commit(isCancelled: () -> Bool = { false }) throws -> HandoffReceipt {
        let snapshot: [HandoffManifest.Item] = try lock.withLock {
            guard !finished else { throw HandoffFailure.writeFailed("session already finished") }
            guard !items.isEmpty else { throw HandoffFailure.noSupportedItem }
            return items
        }
        if isCancelled() { throw HandoffFailure.cancelled }
        let faults = environment.faults
        try faults.reach(.syncItemsDirectory)
        try Durability.syncDirectory(directory.appendingPathComponent("items", isDirectory: true))
        let manifest = HandoffManifest(
            schemaVersion: HandoffManifest.schemaVersion,
            handoffID: handoffID,
            createdAt: environment.now(),
            producer: .init(kind: "share_extension", bundleIdentifier: environment.producerBundleIdentifier,
                            buildVersion: environment.producerBuildVersion),
            items: snapshot,
            totalBytes: snapshot.reduce(0) { $0 + $1.byteCount }
        )
        try manifest.validate(directoryName: handoffID.uuidString)
        // The app's scan refuses a handoff.json over `HandoffManifest.maxBytes`, so committing one would show "Received"
        // for a handoff the app then rejects (G0.3 review R4-02). Refuse it here: the user gets the fallback instead.
        let encoded = try manifest.encoded()
        guard encoded.count <= HandoffManifest.maxBytes else { throw HandoffFailure.manifestTooLarge }
        try AtomicFile.write(
            encoded,
            to: directory.appendingPathComponent(HandoffManifest.fileName),
            policy: .noReplace,
            faults: faults,
            steps: .init(write: .writeManifestTemporary, sync: .syncManifestTemporary,
                         rename: .renameManifest, syncDirectory: .syncHandoffDirectory)
        )
        lock.withLock { finished = true }
        return HandoffReceipt(handoffID: handoffID, itemCount: snapshot.count, totalBytes: manifest.totalBytes)
    }

    /// Failure path: removes everything this session wrote, including a manifest that was renamed but whose
    /// directory sync failed, so a session reported as failed can never be imported later.
    public func discard() {
        lock.withLock { finished = true }
        Durability.removeTree(directory)
        try? Durability.syncDirectory(environment.inbox)
    }

    /// Runs a complete handoff for already-local files (used by tests, the host CLI and the in-app harness).
    /// `SimulatedProcessDeath` propagates without cleanup, like a killed process.
    public static func run(
        environment: HandoffEnvironment,
        files: [(url: URL, contentType: String)],
        isCancelled: @escaping () -> Bool = { false },
        progress: @escaping (UInt64) -> Void = { _ in }
    ) throws -> Result<HandoffReceipt, HandoffFailure> {
        let session = HandoffSession(environment: environment)
        do {
            for file in files {
                try session.addItem(
                    copying: file.url, originalFilename: file.url.lastPathComponent, contentType: file.contentType,
                    preferredExtension: file.url.pathExtension, representation: .fileURL,
                    providerTypeIdentifier: "public.file-url", expectedLength: nil,
                    isCancelled: isCancelled, progress: progress
                )
            }
            return .success(try session.commit(isCancelled: isCancelled))
        } catch let death as SimulatedProcessDeath {
            throw death
        } catch {
            session.discard()
            return .failure(HandoffFailure.from(error))
        }
    }

    /// The shared file's name as metadata: every "/" code point becomes "_", U+0000 is dropped, and the result is cut to
    /// 255 UTF-8 bytes at a character boundary. Code points, not `Character`s: Foundation's `replacingOccurrences(of:
    /// "/", ...)` leaves a "/" that a combining mark follows (one grapheme cluster with it), which the manifest's own
    /// validation then refused, so such a share failed (found in the G0.3 review R4-01 audit; report F18).
    static func cleanFilename(_ name: String, fallback: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars where scalar != "\u{0}" {
            scalars.append(scalar == "/" ? "_" : scalar)
        }
        var cleaned = String(scalars)
        while cleaned.utf8.count > 255 { cleaned.removeLast() }
        return cleaned.isEmpty ? fallback : cleaned
    }
}
