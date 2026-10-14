import Darwin
import Foundation
import SylviaIntakeCore

/// What happens to a handoff directory that never got its manifest.
public struct CleanupPolicy: Sendable, Equatable {
    /// A manifest-less directory whose newest modification is older than this is abandoned and removed.
    /// Younger ones may still be written by a live extension and are left alone. The extension updates
    /// modification times with every chunk it writes. An extension that is still alive but idle for longer
    /// (for example waiting on a slow provider for a later item) loses its directory; its next write then fails
    /// and it shows the fallback, so the policy can cost a retry but never produces a false "Received"
    /// (the directory is claimed with one rename before it is deleted; see `scanEntry`).
    public var abandonAfter: TimeInterval
    /// Handoffs moved to `Staging/Rejected/` (bad manifest, tampered bytes) are kept this long for
    /// "Inspect details", then removed with a cleanup record. They can never be imported.
    public var rejectedRetention: TimeInterval

    public init(abandonAfter: TimeInterval = 3600, rejectedRetention: TimeInterval = 7 * 86_400) {
        self.abandonAfter = abandonAfter
        self.rejectedRetention = rejectedRetention
    }
}

/// The main app's commit sequence for one handoff (plan 8.2 commit journal). The scanner's hook is called
/// right after each step completes, so a test can simulate process death between any two steps.
public enum AcceptStep: String, CaseIterable, Sendable {
    case verified        // manifest valid, every item's size and SHA-256 re-checked (DropAreaImporter: a single
                         // file's snapshot taken and hashed, before its source is checked again)
    case intentRecorded  // journal row in `accepting`
    case moved           // Handoffs/<id> renamed into private staging
    case finished        // journal row `staged` or `needs_review`
}

public struct InboxScanReport: Sendable, Equatable {
    public struct Rejection: Sendable, Equatable {
        public var directoryName: String
        public var reason: String
    }

    public var acceptedJobs: [UUID] = []
    public var recoveredJobs: [UUID] = []
    public var alreadyAccepted: [String] = []
    public var inProgress: [String] = []
    public var abandonedRemoved: [String] = []
    public var rejected: [Rejection] = []
    public var expiredRejectionsRemoved: [String] = []

    public init() {}
}

/// Scans the App Group handoff inbox. Called on launch and on every foreground. Idempotent: scanning any
/// number of times, or crashing at any accept step and scanning again, yields exactly one job per handoff.
public final class InboxScanner: @unchecked Sendable {
    public let inbox: URL
    public let stagingRoot: URL
    public let journal: IntakeJournal
    public let policy: CleanupPolicy
    private let now: @Sendable () -> Date
    private let hook: @Sendable (AcceptStep) throws -> Void
    /// Test seam: called after a manifest-less directory was judged stale and before it is claimed, so a test
    /// can make the extension's commit land in exactly that window.
    private let beforeAbandon: @Sendable (String) -> Void
    private let lock = NSLock()

    public init(
        inbox: URL,
        stagingRoot: URL,
        journal: IntakeJournal,
        policy: CleanupPolicy = CleanupPolicy(),
        now: @escaping @Sendable () -> Date = { Date() },
        hook: @escaping @Sendable (AcceptStep) throws -> Void = { _ in },
        beforeAbandon: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.inbox = inbox
        self.stagingRoot = stagingRoot
        self.journal = journal
        self.policy = policy
        self.now = now
        self.hook = hook
        self.beforeAbandon = beforeAbandon
    }

    var stagedRoot: URL { stagingRoot.appendingPathComponent("Staged", isDirectory: true) }
    var rejectedRoot: URL { stagingRoot.appendingPathComponent("Rejected", isDirectory: true) }
    var abandonedRoot: URL { stagingRoot.appendingPathComponent("Abandoned", isDirectory: true) }

    /// Only `SimulatedProcessDeath` escapes; every other problem is reported per directory.
    public func scan() throws -> InboxScanReport {
        try lock.withLock {
            var report = InboxScanReport()
            try FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
            try recoverUnfinishedAccepts(into: &report)
            try recoverInterruptedClaims()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
            for name in names.sorted() {
                do {
                    try scanEntry(named: name, into: &report)
                } catch let death as SimulatedProcessDeath {
                    throw death
                } catch {
                    report.rejected.append(.init(directoryName: name, reason: String(describing: error)))
                }
            }
            try purgeExpiredRejections(into: &report)
            return report
        }
    }

    /// Removes rejected handoffs older than the retention period. Nothing under Rejected/ can ever be imported.
    private func purgeExpiredRejections(into report: inout InboxScanReport) throws {
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: rejectedRoot.path)) ?? []).sorted() {
            let url = rejectedRoot.appendingPathComponent(name)
            let age = now().timeIntervalSince(newestModification(of: url))
            guard age > policy.rejectedRetention else { continue }
            let bytes = treeByteCount(url)
            Durability.removeTree(url)
            try journal.recordCleanup(.init(directoryName: name, reason: "rejected_expired", byteCount: bytes, removedAt: now()))
            report.expiredRejectionsRemoved.append(name)
        }
    }

    // MARK: - Recovery

    private func recoverUnfinishedAccepts(into report: inout InboxScanReport) throws {
        for job in journal.jobs where job.state == .accepting && job.route == .shareExtension {
            guard let handoffID = job.handoffID else { continue }
            let source = inbox.appendingPathComponent(handoffID.uuidString, isDirectory: true)
            let destination = stagingRoot.appendingPathComponent(job.stagedDirectory, isDirectory: true)
            let sourceExists = (try? Durability.lstatInfo(source)) != nil
            let destinationExists = (try? Durability.lstatInfo(destination)) != nil
            do {
                switch (sourceExists, destinationExists) {
                case (false, true):
                    break  // The move happened; only the journal update was lost.
                case (true, false), (true, true):
                    // (true, true): a cross-volume copy was interrupted; the source is authoritative.
                    if destinationExists { Durability.removeTree(destination) }
                    do {
                        _ = try verifiedManifest(in: source, name: handoffID.uuidString)
                    } catch {
                        // The bytes no longer match what was verified before the intent: end the job as failed
                        // instead of retrying it on every scan.
                        try failStaged(job, at: source, reason: "verification failed during recovery: \(error)", into: &report)
                        continue
                    }
                    try move(source, to: destination)
                case (false, false):
                    var failed = job
                    failed.state = .failedFinal
                    try journal.upsert(failed)
                    report.rejected.append(.init(directoryName: handoffID.uuidString, reason: "bytes missing during recovery"))
                    continue
                }
                guard stagedItemsIntact(destination, items: job.items) else {
                    try failStaged(job, at: destination, reason: "staged items incomplete during recovery", into: &report)
                    continue
                }
                _ = try journal.finishStaging(jobID: job.jobID)
                try hook(.finished)
                report.recoveredJobs.append(job.jobID)
            } catch let death as SimulatedProcessDeath {
                throw death
            } catch {
                report.rejected.append(.init(directoryName: handoffID.uuidString, reason: String(describing: error)))
            }
        }
    }

    // MARK: - Abandoned handoffs

    enum AbandonOutcome: Equatable {
        case removed(byteCount: UInt64)
        /// The extension committed its manifest between the staleness check and the claim: never deleted.
        case committedMeanwhile
    }

    /// Takes a stale, manifest-less handoff directory out of the extension's reach with one rename into private
    /// staging, then checks again for a manifest. Deleting in place would leave a window in which a slow but
    /// live extension renames its manifest into a directory whose items are being deleted, and could then report
    /// receipt for bytes that are gone. After the claim the extension's next path-based step (creating the next
    /// item, the temporary manifest, the rename or the directory sync) fails, so it shows the fallback; a manifest
    /// that made it in before the claim is put back and imported by the next scan.
    func claimAbandoned(_ url: URL, name: String) throws -> AbandonOutcome {
        try FileManager.default.createDirectory(at: abandonedRoot, withIntermediateDirectories: true)
        let claimed = abandonedRoot.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        guard renamex_np(url.path, claimed.path, UInt32(RENAME_EXCL)) == 0 else {
            guard errno == EXDEV else { throw IntakeIOError("claim abandoned handoff") }
            // Inbox and staging on different volumes (never the case for an app and its App Group on iOS):
            // re-check immediately before deleting in place.
            if try Durability.lstatInfo(url.appendingPathComponent(HandoffManifest.fileName)) != nil { return .committedMeanwhile }
            let bytes = treeByteCount(url)
            Durability.removeTree(url)
            try? Durability.syncDirectory(inbox)
            return .removed(byteCount: bytes)
        }
        try Durability.syncDirectory(inbox)
        try Durability.syncDirectory(abandonedRoot)
        if try Durability.lstatInfo(claimed.appendingPathComponent(HandoffManifest.fileName)) != nil {
            try Durability.renameNoReplace(claimed, to: url)
            try Durability.syncDirectory(abandonedRoot)
            return .committedMeanwhile
        }
        let bytes = treeByteCount(claimed)
        Durability.removeTree(claimed)
        try? Durability.syncDirectory(abandonedRoot)
        return .removed(byteCount: bytes)
    }

    /// A crash between a claim and its deletion leaves a directory under Abandoned/. One that holds a manifest is
    /// put back into the inbox (its original name is the first 36 characters); anything else is removed.
    private func recoverInterruptedClaims() throws {
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: abandonedRoot.path)) ?? []).sorted() {
            let claimed = abandonedRoot.appendingPathComponent(name, isDirectory: true)
            let original = String(name.prefix(36))
            if UUID(uuidString: original) != nil,
               (try? Durability.lstatInfo(claimed.appendingPathComponent(HandoffManifest.fileName))) != nil,
               (try? Durability.lstatInfo(inbox.appendingPathComponent(original))) == nil {
                try Durability.renameNoReplace(claimed, to: inbox.appendingPathComponent(original, isDirectory: true))
            } else {
                Durability.removeTree(claimed)
            }
        }
    }

    // MARK: - One inbox entry

    private func scanEntry(named name: String, into report: inout InboxScanReport) throws {
        let url = inbox.appendingPathComponent(name)
        guard let info = try Durability.lstatInfo(url) else { return }
        guard info.isDirectory, let handoffID = UUID(uuidString: name), PathBytes.equal(handoffID.uuidString, name) else {
            // Not something the extension writes. Remove only once it is old enough to be certainly stale.
            if isStale(newestModification(of: url)) {
                let bytes = treeByteCount(url)
                Durability.removeTree(url)
                try journal.recordCleanup(.init(directoryName: name, reason: "unexpected_entry", byteCount: bytes, removedAt: now()))
                report.abandonedRemoved.append(name)
            }
            return
        }
        if journal.job(handoffID: handoffID) != nil {
            report.alreadyAccepted.append(name)
            return
        }
        let manifestURL = url.appendingPathComponent(HandoffManifest.fileName)
        guard try Durability.lstatInfo(manifestURL) != nil else {
            // No manifest: the extension either is still writing or died. Nothing was reported received.
            if isStale(newestModification(of: url)) {
                beforeAbandon(name)
                switch try claimAbandoned(url, name: name) {
                case let .removed(bytes):
                    try journal.recordCleanup(.init(directoryName: name, reason: "abandoned_incomplete", byteCount: bytes, removedAt: now()))
                    report.abandonedRemoved.append(name)
                case .committedMeanwhile:
                    report.inProgress.append(name)
                }
            } else {
                report.inProgress.append(name)
            }
            return
        }

        let manifest: HandoffManifest
        do {
            manifest = try verifiedManifest(in: url, name: name)
        } catch {
            try quarantine(url, name: name, reason: String(describing: error))
            report.rejected.append(.init(directoryName: name, reason: String(describing: error)))
            return
        }
        try hook(.verified)

        let job = IntakeJournal.Job(
            jobID: UUID(), route: .shareExtension, state: .accepting, handoffID: handoffID,
            stagedDirectory: "Staged/\(name)",
            items: manifest.items.map {
                .init(relativePath: $0.storedPath, byteCount: $0.byteCount, sha256: $0.sha256,
                      contentType: $0.contentType, originalFilename: $0.originalFilename)
            },
            duplicateOf: nil, createdAt: now()
        )
        try journal.upsert(job)
        try hook(.intentRecorded)
        let staged = stagedRoot.appendingPathComponent(name, isDirectory: true)
        try move(url, to: staged)
        try hook(.moved)
        // Until the move the directory was within the extension's reach: an extension whose commit failed after its
        // manifest rename deletes its directory (HandoffSession.discard). After the move nothing else can touch it,
        // so re-checking the listing and sizes here shows the staged bytes are the ones verified above.
        guard stagedItemsIntact(staged, items: job.items) else {
            try failStaged(job, at: staged, reason: "items changed between verification and the move", into: &report)
            return
        }
        _ = try journal.finishStaging(jobID: job.jobID)
        try hook(.finished)
        report.acceptedJobs.append(job.jobID)
    }

    /// Reads and validates handoff.json, then re-checks every item's type, size and SHA-256 against it.
    /// The items directory must contain exactly the manifest's items, compared as bytes (G0.3 review R4-01).
    func verifiedManifest(in directory: URL, name: String) throws -> HandoffManifest {
        let manifestURL = directory.appendingPathComponent(HandoffManifest.fileName)
        let manifest = try HandoffManifest.read(contentsOf: manifestURL)
        try manifest.validate(directoryName: name)
        let itemsDirectory = directory.appendingPathComponent("items", isDirectory: true)
        let present = try FileManager.default.contentsOfDirectory(atPath: itemsDirectory.path)
        let expected = manifest.items.map { String($0.storedPath.dropFirst("items/".count)) }
        guard InboxScanner.sameNames(present, expected) else { throw HandoffVerificationError.unexpectedFiles }
        for item in manifest.items {
            let itemURL = directory.appendingPathComponent(item.storedPath)
            guard let info = try Durability.lstatInfo(itemURL), info.isRegularFile else {
                throw HandoffVerificationError.itemNotRegularFile
            }
            guard UInt64(info.st_size) == item.byteCount else { throw HandoffVerificationError.sizeMismatch }
            guard PathBytes.equal(try FileDigest.sha256(of: itemURL).sha256, item.sha256) else {
                throw HandoffVerificationError.digestMismatch
            }
        }
        return manifest
    }

    private func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
            try Durability.syncDirectory(destination.deletingLastPathComponent())
            try Durability.syncDirectory(source.deletingLastPathComponent())
            return
        }
        guard errno == EXDEV else { throw IntakeIOError("rename") }
        // Different volumes: copy every file, then publish with one rename, then remove the source.
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial", isDirectory: true)
        Durability.removeTree(partial)
        try FileManager.default.createDirectory(at: partial.appendingPathComponent("items"), withIntermediateDirectories: true)
        let copier = StreamingCopier()
        for relative in try FileManager.default.subpathsOfDirectory(atPath: source.path) {
            let from = source.appendingPathComponent(relative)
            guard let info = try Durability.lstatInfo(from), info.isRegularFile else { continue }
            _ = try copier.copy(from: from, toNewFile: partial.appendingPathComponent(relative))
        }
        try Durability.renameNoReplace(partial, to: destination)
        Durability.removeTree(source)
    }

    /// Cheap post-move check: `items/` holds exactly the journaled items, each a regular file of the journaled size.
    /// Contents were hashed before the move and the extension closes every item before it commits, so between the
    /// hash and the move only removal (not rewriting) is possible, and removal shows up here.
    func stagedItemsIntact(_ directory: URL, items: [IntakeJournal.StagedItem]) -> Bool {
        let itemsDirectory = directory.appendingPathComponent("items", isDirectory: true)
        guard let present = try? FileManager.default.contentsOfDirectory(atPath: itemsDirectory.path),
              InboxScanner.sameNames(present, items.map { String($0.relativePath.dropFirst("items/".count)) }) else { return false }
        for item in items {
            guard let info = try? Durability.lstatInfo(directory.appendingPathComponent(item.relativePath)),
                  info.isRegularFile, UInt64(info.st_size) == item.byteCount else { return false }
        }
        return true
    }

    /// A journaled job whose staged bytes are not intact: the job becomes `failed_final` (reported, never hidden)
    /// and the directory moves to Rejected/ for "Inspect details".
    private func failStaged(_ job: IntakeJournal.Job, at staged: URL, reason: String,
                            into report: inout InboxScanReport) throws {
        let name = job.handoffID?.uuidString ?? job.jobID.uuidString
        try quarantine(staged, name: name, reason: reason)
        var failed = job
        failed.state = .failedFinal
        try journal.upsert(failed)
        report.rejected.append(.init(directoryName: name, reason: reason))
    }

    private func quarantine(_ url: URL, name: String, reason: String) throws {
        try FileManager.default.createDirectory(at: rejectedRoot, withIntermediateDirectories: true)
        let target = rejectedRoot.appendingPathComponent(name + "-" + UUID().uuidString, isDirectory: true)
        let bytes = treeByteCount(url)
        if renamex_np(url.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            Durability.removeTree(url)
        }
        try journal.recordCleanup(.init(directoryName: name, reason: "rejected: \(reason)", byteCount: bytes, removedAt: now()))
    }

    /// The same set of names, compared as UTF-8 bytes (not with String's canonical equivalence).
    static func sameNames(_ a: [String], _ b: [String]) -> Bool {
        Set(a.map { Array($0.utf8) }) == Set(b.map { Array($0.utf8) })
    }

    private func isStale(_ newest: Date) -> Bool {
        let age = now().timeIntervalSince(newest)
        return age > policy.abandonAfter   // a future timestamp (negative age) is never stale
    }

    /// Newest modification time of the entry and everything under it (without following links).
    func newestModification(of url: URL) -> Date {
        var newest = (try? Durability.lstatInfo(url))?.modificationDate ?? .distantPast
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            while let relative = enumerator.nextObject() as? String {
                if let info = try? Durability.lstatInfo(url.appendingPathComponent(relative)) {
                    newest = max(newest, info.modificationDate)
                }
            }
        }
        return newest
    }

    private func treeByteCount(_ url: URL) -> UInt64 {
        var total: UInt64 = 0
        if let info = try? Durability.lstatInfo(url), info.isRegularFile { return UInt64(info.st_size) }
        if let enumerator = FileManager.default.enumerator(atPath: url.path) {
            while let relative = enumerator.nextObject() as? String {
                if let info = try? Durability.lstatInfo(url.appendingPathComponent(relative)), info.isRegularFile {
                    total += UInt64(info.st_size)
                }
            }
        }
        return total
    }
}

public enum HandoffVerificationError: Error, Equatable, Sendable {
    case unexpectedFiles
    case itemNotRegularFile
    case sizeMismatch
    case digestMismatch
}
