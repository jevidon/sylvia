import Darwin
import Foundation
import SylviaImportHandoff
import SylviaIntakeCore
import SylviaPack
import UniformTypeIdentifiers

/// User-initiated imports from the Finder-visible drop area (plan 8.1 "Wired Finder", 8.5, 16.4) and single-file
/// open-in / AirDrop / document-picker imports. All of them end in the same journal (`IntakeJournal`), so
/// duplicates are handled identically whatever the route (T08).
///
/// What happens to the inbound copy (ADR-0010 section 5, plan 16.4 "cleaned up only after successful import or
/// explicit user action"):
/// - A bundle in the drop area is removed once its job is durably staged (or flagged `needs_review` as a duplicate,
///   whose bytes are also staged), and only if it is still the same file that was validated (device, inode, size and
///   modification time unchanged); otherwise it stays. A rejected bundle stays until the user removes it.
/// - A raw file that Finder copied into the drop area stays after its import until the user removes it: without a
///   manifest nothing proves Finder had finished, so removing it could cut off a copy still in progress.
/// - A system open-in or AirDrop copy in `Documents/Inbox` is removed whatever the outcome: the sender still has the
///   original, and Sylvia never keeps a second, Finder-visible copy. A copy left there by a crash is listed in the
///   drop area (as `Inbox/<name>`) so the user can import or remove it.
/// - A document-picker source is never modified or removed (I-08).
///
/// What the app can and cannot know about an external writer (recorded in the G0.3 report):
/// - Finder's file-sharing copy is performed by the system on the app's behalf; nothing indicates that it takes
///   part in file coordination, so `NSFileCoordinator` cannot be relied on to wait for it.
/// - A file's size or modification time staying unchanged does not prove the writer finished (plan 8.5).
/// - What the app can prove is whether the bytes it has are a complete, valid pack. It snapshots the file
///   (APFS clone, inside a coordinated read) and validates the snapshot; a partial copy fails validation.
/// - For a raw file (no manifest) it can prove nothing about completeness: the snapshot is whatever Finder had written
///   when the user tapped Import. If the file changes while it is being imported, the copy is evidently still running
///   and the import is refused (`stillBeingWritten`); a copy that is paused or has stopped is not detected. The user
///   is told to wait for Finder; the type's own validation comes later (plan 8.2 `validating`).
public final class DropAreaImporter: @unchecked Sendable {
    public struct DropItem: Sendable, Equatable {
        public enum Kind: String, Sendable { case bundle, file, unsupported }
        public let name: String
        public let byteCount: UInt64
        public let modified: Date
        public let kind: Kind
    }

    public enum ImportError: Error, Equatable, Sendable, CustomStringConvertible {
        case notInDropArea
        case notAFile
        case unsupportedType
        case coordinationFailed
        /// A raw drop-area file changed between its snapshot and the end of hashing: Finder (or another writer that
        /// does not coordinate) is still copying it. Nothing was imported; the file stays.
        case stillBeingWritten
        case rejected(PackRejection)
        /// The volume lacks the space to import; plan 8.4 asks the message to name the additional space.
        case insufficientSpace(additionalBytesNeeded: UInt64)
        case io(String)
        /// Test seam only: the hook simulated process death; nothing was cleaned up, as after a real kill.
        case simulatedProcessDeath

        public var description: String {
            switch self {
            case .notInDropArea: "not a top-level item in the drop area"
            case .notAFile: "not a regular file"
            case .unsupportedType: "unsupported file type"
            case .coordinationFailed: "file coordination failed"
            case .stillBeingWritten: "the file changed while it was being imported (still being copied?): wait until the copy has finished, then import again"
            case let .rejected(r): "bundle rejected: \(r)"
            case let .insufficientSpace(n):
                "not enough space: free up \(ByteCountFormatter.string(fromByteCount: Int64(clamping: n), countStyle: .file)) more (\(n) bytes)"
            case let .io(s): s
            case .simulatedProcessDeath: "simulated process death"
            }
        }
    }

    /// What `recoverInterruptedImports` did on launch.
    public struct RecoveryReport: Sendable, Equatable {
        public var finished: [UUID] = []
        public var failed: [UUID] = []
        public var removedExtractions: [String] = []
        public init() {}
    }

    public let layout: StorageLayout
    public let journal: IntakeJournal
    public let reader: PackReader
    /// Called right after each commit step of `publish` (`.intentRecorded`, `.moved`, `.finished`), and for a single
    /// file after its snapshot is hashed (`.verified`); a test throws `SimulatedProcessDeath` to stop there without
    /// cleanup, or acts on the source to stand in for a writer that is still copying.
    private let hook: @Sendable (AcceptStep) throws -> Void

    public init(layout: StorageLayout, journal: IntakeJournal, reader: PackReader = PackReader(),
                hook: @escaping @Sendable (AcceptStep) throws -> Void = { _ in }) {
        self.layout = layout
        self.journal = journal
        self.reader = reader
        self.hook = hook
    }

    /// The system's folder for open-in and AirDrop copies (LSSupportsOpeningDocumentsInPlace = NO).
    public static let systemInboxName = "Inbox"

    /// Top-level files in Documents, then any open-in copies left in Documents/Inbox (named `Inbox/<name>`), which
    /// only a crash during their import leaves behind.
    public func listDropArea() -> [DropItem] {
        func items(in directory: URL, prefix: String) -> [DropItem] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return names.sorted().compactMap { name in
                guard !PathBytes.hasPrefix(name, ".") else { return nil }   // hidden: the first byte is "."
                guard let info = try? Durability.lstatInfo(directory.appendingPathComponent(name)), info.isRegularFile else {
                    return nil
                }
                let ext = (name as NSString).pathExtension.lowercased()
                let kind: DropItem.Kind = ext == PackLayout.fileExtension ? .bundle
                    : SupportedContent.supportedType(forFileExtension: ext) != nil ? .file : .unsupported
                return DropItem(name: prefix + name, byteCount: UInt64(info.st_size), modified: info.modificationDate, kind: kind)
            }
        }
        return items(in: layout.documents, prefix: "")
            + items(in: systemInbox, prefix: DropAreaImporter.systemInboxName + "/")
    }

    var systemInbox: URL { layout.documents.appendingPathComponent(DropAreaImporter.systemInboxName, isDirectory: true) }

    /// Launch-time recovery for the routes this importer owns (Finder bundle, open-in, document picker); the
    /// share-extension route is recovered by `InboxScanner`. Same journal idea as plan 8.2:
    /// - A job in `accepting` was journaled only after its bytes were completely copied (or extracted and
    ///   validated) and synced under `Extracting/<job id>`, so recovery finishes the move and the job.
    /// - A job in `accepting` whose bytes are in neither place is marked `failed_final` (reported, never hidden).
    /// - Anything else under `Extracting/` has no commit intent: it is an interrupted copy or extraction and is
    ///   removed. The bundle itself is still in Documents, so the user can import it again.
    @discardableResult
    public func recoverInterruptedImports() -> RecoveryReport {
        var report = RecoveryReport()
        var protected = Set<String>()
        for job in journal.jobs where job.state == .accepting && job.route != .shareExtension {
            let staged = layout.staging.appendingPathComponent(job.stagedDirectory, isDirectory: true)
            let extracted = layout.extracting.appendingPathComponent(job.jobID.uuidString, isDirectory: true)
            do {
                if (try Durability.lstatInfo(staged)) == nil {
                    guard (try Durability.lstatInfo(extracted)) != nil else {
                        var failed = job
                        failed.state = .failedFinal
                        try journal.upsert(failed)
                        report.failed.append(job.jobID)
                        continue
                    }
                    try ensureDirectoryThrowing(staged.deletingLastPathComponent())
                    try Durability.renameNoReplace(extracted, to: staged)
                }
                _ = try journal.finishStaging(jobID: job.jobID)
                report.finished.append(job.jobID)
            } catch {
                // Leave the journal entry and the bytes for the next launch; never delete validated bytes here.
                protected.insert(job.jobID.uuidString)
            }
        }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: layout.extracting.path)) ?? []
        for name in names.sorted() where !protected.contains(name) {
            Durability.removeTree(layout.extracting.appendingPathComponent(name))
            report.removedExtractions.append(name)
        }
        return report
    }

    /// Imports the drop-area item the user chose (the Import button; never automatic):
    /// - a `.sylviapack` the user copied into Documents with Finder, through the bundle importer (validated against its
    ///   manifest, so a partial copy is rejected);
    ///   After a durable import the bundle is removed if it is still the file that was validated (plan 16.4); a rejected
    ///   bundle stays until the user removes it;
    /// - a raw supported file (EPUB, PDF, text, Markdown, audio) copied with Finder, through the single-file importer
    ///   (plan 8.5 allows it: user-initiated, coordinated). Its bytes end `staged`, owned but not trusted; checking that
    ///   they are a whole, readable book is the pipeline's later validation (plan 8.2 `validating`, the G0.1 adapters).
    ///   Unlike a bundle, nothing here can prove Finder had finished: a file that changes during its import is refused
    ///   as still being written, but one whose copy is paused or has stopped is staged as the partial bytes it had
    ///   (plan 8.5; G0.3 report F15), which is why large transfers use the bundle. For the same reason the raw file is
    ///   never removed automatically: an unchanged identity right after the snapshot cannot rule out a writer that is
    ///   still copying, and removing its file would lose the rest of the copy. It stays until the user removes it; the
    ///   staged APFS clone shares its blocks, so keeping it costs no extra space until one changes;
    /// - an open-in copy left as `Inbox/<name>`, as an opened file.
    public func importDropAreaItem(named name: String) async throws(ImportError) -> IntakeJournal.Job {
        let source = try dropAreaFile(named: name)
        if isSystemInboxCopy(source) {
            return try await importOpenedFile(at: source, route: .openIn)
        }
        if source.pathExtension.lowercased() == PackLayout.fileExtension {
            return try await importBundle(at: source, route: .documentsBundle, afterSuccess: .removeIfUnchanged)
        }
        return try importSingleFile(at: source, route: .documentsFile)
    }

    /// Open-in or AirDrop (the system's `onOpenURL`): a .sylviapack goes through the bundle importer, anything else
    /// through the single-file importer. A copy the system placed in `Documents/Inbox` is removed whatever the
    /// outcome; the sender keeps the original.
    public func importOpenedFile(at url: URL, route: IntakeJournal.Route) async throws(ImportError) -> IntakeJournal.Job {
        let inboxCopy = isSystemInboxCopy(url)
        defer {
            if inboxCopy { removeSystemInboxCopy(url) }
        }
        if url.pathExtension.lowercased() == PackLayout.fileExtension {
            return try await importBundle(at: url, route: route, afterSuccess: .keep)
        }
        return try importSingleFile(at: url, route: route)
    }

    enum AfterSuccess { case keep, removeIfUnchanged }

    private func importBundle(at source: URL, route: IntakeJournal.Route,
                              afterSuccess: AfterSuccess) async throws(ImportError) -> IntakeJournal.Job {
        let jobID = UUID()
        try ensureDirectory(layout.extracting)
        let snapshot = layout.extracting.appendingPathComponent("\(jobID.uuidString).sylviapack")
        let extracted = layout.extracting.appendingPathComponent(jobID.uuidString, isDirectory: true)
        defer { Durability.removeTree(snapshot) }
        let identity = try coordinatedSnapshot(of: source, to: snapshot)
        let validated: ValidatedPack
        do {
            validated = try await reader.extract(snapshot, to: extracted)
        } catch {
            if error.code == .insufficientSpace, let needed = error.additionalBytesNeeded {
                throw .insufficientSpace(additionalBytesNeeded: needed)
            }
            throw .rejected(error)
        }
        let job = IntakeJournal.Job(
            jobID: jobID, route: route, state: .accepting, handoffID: nil,
            stagedDirectory: "Staged/\(jobID.uuidString)",
            items: validated.manifest.files.map {
                .init(relativePath: $0.path, byteCount: $0.size, sha256: $0.sha256,
                      contentType: $0.mediaType, originalFilename: ($0.path as NSString).lastPathComponent)
            },
            duplicateOf: nil, createdAt: Date()
        )
        let published = try publish(job, from: extracted)
        if afterSuccess == .removeIfUnchanged { removeIfUnchanged(source, identity: identity) }
        return published
    }

    /// One supported file (document picker, a raw drop-area file, or open-in through `importOpenedFile`): coordinated,
    /// security-scoped snapshot into private staging. On APFS the snapshot is a clone (no second copy of the bytes; the
    /// clone is immutable, so the hash describes exactly what is kept); across volumes it is a streaming copy. The
    /// source is never modified or removed here.
    ///
    /// A raw drop-area file (`.documentsFile`) was written by Finder, which does not coordinate, so the coordinated
    /// read cannot wait for it. After hashing the snapshot, its source is checked again: if its device, inode, size or
    /// modification time changed since the snapshot, the copy is still going on and the import is refused
    /// (`stillBeingWritten`) rather than staging part of the file. An unchanged file proves nothing (plan 8.5): a copy
    /// that is paused, or has stopped, is not detected; its bytes are staged, not trusted (G0.3 report F15).
    public func importSingleFile(at url: URL, route: IntakeJournal.Route) throws(ImportError) -> IntakeJournal.Job {
        guard let type = SupportedContent.supportedType(forFileExtension: url.pathExtension) else { throw .unsupportedType }
        let jobID = UUID()
        let extracted = layout.extracting.appendingPathComponent(jobID.uuidString, isDirectory: true)
        let storedPath = HandoffManifest.storedPath(ordinal: 0, preferredExtension: url.pathExtension)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var copy: Result<(CopyResult, FileIdentity), any Error> = .failure(ImportError.coordinationFailed)
        var coordinationError: NSError?
        do {
            try FileManager.default.createDirectory(at: extracted.appendingPathComponent("items"), withIntermediateDirectories: true)
        } catch { throw .io("staging directory") }
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            copy = Result { try DropAreaImporter.cloneOrCopy(readURL, to: extracted.appendingPathComponent(storedPath)) }
        }
        guard coordinationError == nil else {
            Durability.removeTree(extracted)
            throw .coordinationFailed
        }
        let result: CopyResult
        let identity: FileIdentity
        do {
            (result, identity) = try copy.get()
            // The copy itself was synced by the copier; make its directory entries durable too, so a commit intent
            // recorded next never points at bytes a power loss could still drop (recoverInterruptedImports trusts it).
            try Durability.syncDirectory(extracted.appendingPathComponent("items", isDirectory: true))
            try Durability.syncDirectory(extracted)
            try Durability.syncDirectory(layout.extracting)
        } catch {
            Durability.removeTree(extracted)
            throw .io(String(describing: error))
        }
        do {
            try hook(.verified)
        } catch is SimulatedProcessDeath {
            throw .simulatedProcessDeath   // a killed process cleans nothing up
        } catch {
            Durability.removeTree(extracted)
            throw .io(String(describing: error))
        }
        if route == .documentsFile {
            let now = try? Durability.lstatInfo(url)
            guard let now, now.isRegularFile, FileIdentity(now) == identity else {
                Durability.removeTree(extracted)
                throw .stillBeingWritten
            }
        }
        let job = IntakeJournal.Job(
            jobID: jobID, route: route, state: .accepting, handoffID: nil,
            stagedDirectory: "Staged/\(jobID.uuidString)",
            items: [.init(relativePath: storedPath, byteCount: result.byteCount, sha256: result.sha256,
                          contentType: type.identifier, originalFilename: url.lastPathComponent)],
            duplicateOf: nil, createdAt: Date()
        )
        return try publish(job, from: extracted)
    }

    /// Explicit removal of an item from the drop area (including an `Inbox/<name>` leftover).
    public func removeFromDropArea(named name: String) throws(ImportError) {
        let url = try dropAreaFile(named: name)
        do { try FileManager.default.removeItem(at: url) } catch { throw .io("remove") }
    }

    // MARK: - Helpers

    /// A top-level drop-area file, or `Inbox/<name>` for a system open-in copy. Names are tested byte by byte: a "/" that
    /// a combining mark follows is invisible to Character-based `contains` and `hasPrefix`, and the first version
    /// resolved "../" + U+0301 + "x" to a file beside Documents (report finding F18).
    private func dropAreaFile(named name: String) throws(ImportError) -> URL {
        var directory = layout.documents
        var leaf = name
        let inboxPrefix = DropAreaImporter.systemInboxName + "/"
        if PathBytes.hasPrefix(name, inboxPrefix) {
            directory = systemInbox
            leaf = String(decoding: name.utf8.dropFirst(inboxPrefix.utf8.count), as: UTF8.self)
        }
        guard !leaf.utf8.isEmpty, !PathBytes.containsSeparator(leaf), !PathBytes.isDotOrDotDot(leaf),
              !(directory == layout.documents && PathBytes.equal(leaf, DropAreaImporter.systemInboxName)) else {
            throw .notInDropArea
        }
        let url = directory.appendingPathComponent(leaf)
        guard let info = try? Durability.lstatInfo(url) else { throw .notInDropArea }
        guard info.isRegularFile else { throw .notAFile }
        return url
    }

    func isSystemInboxCopy(_ url: URL) -> Bool {
        let inbox = systemInbox.standardizedFileURL.resolvingSymlinksInPath().path
        return PathBytes.hasPrefix(url.standardizedFileURL.resolvingSymlinksInPath().path, inbox + "/")
    }

    private func removeSystemInboxCopy(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// What identifies the file that was snapshotted: if any of these differ later, it is not the same file.
    /// What identifies a file's state without reading it: device, inode, size and modification time (nanoseconds).
    /// Public so the harness and tests can show that a picked file is left untouched (review R3-05).
    public struct FileIdentity: Equatable, Sendable, CustomStringConvertible {
        public let device: Int32
        public let inode: UInt64
        public let size: Int64
        public let modifiedSeconds: Int
        public let modifiedNanoseconds: Int

        public init(_ info: stat) {
            device = info.st_dev
            inode = info.st_ino
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
        }

        /// The identity of the file at `url` (not following a final symbolic link), or nil when there is none.
        public static func of(_ url: URL) -> FileIdentity? {
            (try? Durability.lstatInfo(url)).flatMap { $0 }.map(FileIdentity.init)
        }

        public var description: String {
            "device \(device), inode \(inode), \(size) bytes, modified \(modifiedSeconds).\(String(format: "%09d", modifiedNanoseconds))"
        }
    }

    /// Takes a private, immutable snapshot of the file while holding a coordinated read: an APFS clone when the
    /// volume supports it (constant time and space), otherwise a streaming copy. Returns the identity of the file
    /// that was cloned, read from the same open descriptor.
    private func coordinatedSnapshot(of source: URL, to snapshot: URL) throws(ImportError) -> FileIdentity {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var outcome: Result<FileIdentity, any Error> = .failure(ImportError.coordinationFailed)
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [.withoutChanges], error: &coordinationError) { readURL in
            outcome = Result {
                let fd = open(readURL.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
                guard fd >= 0 else { throw IntakeIOError("open") }
                defer { close(fd) }
                var info = stat()
                guard fstat(fd, &info) == 0 else { throw IntakeIOError("fstat") }
                guard info.isRegularFile else { throw CopyFailure.sourceNotRegularFile }
                if fclonefileat(fd, AT_FDCWD, snapshot.path, 0) != 0 {
                    guard errno == ENOTSUP || errno == EXDEV else { throw IntakeIOError("clonefile") }
                    _ = try StreamingCopier().copy(from: readURL, toNewFile: snapshot)
                }
                return FileIdentity(info)
            }
        }
        guard coordinationError == nil else { throw .coordinationFailed }
        do { return try outcome.get() } catch { throw .io(String(describing: error)) }
    }

    /// Removes a drop-area file after a durable import, inside a coordinated delete, only if it is still the file that
    /// was snapshotted (Finder may have replaced it with a new copy meanwhile). Failure leaves the file in place; the
    /// import itself has already succeeded.
    private func removeIfUnchanged(_ url: URL, identity: FileIdentity) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [.forDeleting], error: &coordinationError) { writeURL in
            guard let info = try? Durability.lstatInfo(writeURL), info.isRegularFile, FileIdentity(info) == identity else { return }
            _ = unlink(writeURL.path)
        }
    }

    /// Snapshot of one file into a new private file: an APFS clone of the open descriptor when possible (hashed after
    /// cloning, so the digest describes the immutable clone), otherwise a streaming copy (which itself fails if the
    /// source changes while it copies). Mode 0600, synced. Also returns the source's identity, read from the same open
    /// descriptor just before the snapshot.
    static func cloneOrCopy(_ source: URL, to destination: URL) throws -> (CopyResult, FileIdentity) {
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw IntakeIOError("open source") }
        var closed = false
        defer { if !closed { close(fd) } }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw IntakeIOError("fstat source") }
        guard info.isRegularFile else { throw CopyFailure.sourceNotRegularFile }
        let identity = FileIdentity(info)
        if fclonefileat(fd, AT_FDCWD, destination.path, 0) == 0 {
            closed = true
            close(fd)
            let out = open(destination.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard out >= 0 else { throw IntakeIOError("open clone") }
            defer { close(out) }
            guard fchmod(out, 0o600) == 0 else { throw IntakeIOError("fchmod clone") }
            try Durability.fullSync(fd: out)
            return (try FileDigest.sha256(of: destination), identity)
        }
        guard errno == ENOTSUP || errno == EXDEV else { throw IntakeIOError("clonefile") }
        return (try StreamingCopier().copy(from: source, toNewFile: destination), identity)
    }

    /// Commit sequence (plan 8.2): the bytes under `Extracting/<job id>` are complete and synced; record the
    /// intent, move them into `Staging/Staged/<job id>` with one rename, then mark the job staged (or
    /// needs_review). A crash between steps is finished by `recoverInterruptedImports` on the next launch.
    private func publish(_ job: IntakeJournal.Job, from extracted: URL) throws(ImportError) -> IntakeJournal.Job {
        let staged = layout.staging.appendingPathComponent(job.stagedDirectory, isDirectory: true)
        do {
            try journal.upsert(job)
        } catch {
            Durability.removeTree(extracted)
            throw .io("journal: \(error)")
        }
        do {
            try hook(.intentRecorded)
            try ensureDirectoryThrowing(staged.deletingLastPathComponent())
            try Durability.renameNoReplace(extracted, to: staged)
            try hook(.moved)
            let finished = try journal.finishStaging(jobID: job.jobID)
            try hook(.finished)
            return finished
        } catch is SimulatedProcessDeath {
            throw .simulatedProcessDeath   // a killed process cleans nothing up
        } catch {
            // Not a crash: the intent exists, so record the outcome instead of leaving a dangling `accepting` row.
            Durability.removeTree(extracted)
            Durability.removeTree(staged)
            var failed = job
            failed.state = .failedFinal
            try? journal.upsert(failed)
            throw .io(String(describing: error))
        }
    }

    private func ensureDirectory(_ url: URL) throws(ImportError) {
        do { try ensureDirectoryThrowing(url) } catch { throw .io("create directory") }
    }

    private func ensureDirectoryThrowing(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
